"""Real Linux identities, fresh cgroup-v2 leaves and an independent marker/ledger oracle."""
import array
import contextlib
import errno
import fcntl
import json
import os
from pathlib import Path
import pwd
import signal
import shutil
import socket
import struct
import subprocess
import sys
import time
import uuid

from test_receipt_import import LE, OUT, STORE, fixture, sha
from test_marker_approval import binding, identity, line, server

BIN=OUT/'reconcile'
CG=Path('/sys/fs/cgroup')


@contextlib.contextmanager
def group():
    leaf=CG/('warband-marker-'+uuid.uuid4().hex)
    leaf.mkdir()
    try:
        for name,value in [('memory.max','33554432'),('memory.swap.max','0'),('pids.max','1')]:
            (leaf/name).write_text(value)
            assert (leaf/name).read_text().strip()==value
        yield leaf
    finally:
        if (leaf/'cgroup.procs').read_text():
            (leaf/'cgroup.kill').write_text('1')
        leaf.rmdir()


def install(f,genesis,probe=None):
    used={p.pw_uid for p in pwd.getpwall()} | {f.runtime,f.operator,f.custodian}
    uid=next(u for u in range(50000,60000) if u not in used)
    (f.root/'intake.anchor').write_bytes(STORE+LE(1)+LE(0)+genesis+struct.pack('<I',f.custodian))
    (f.root/'approval.ids').write_bytes(struct.pack('<II',f.runtime,f.operator))
    (f.root/'worker.uid').write_bytes(struct.pack('<I',uid))
    (f.root/'attempts').mkdir(mode=0o700)
    os.chown(f.root/'attempts',f.runtime,f.runtime)
    shutil.copy2(BIN/('worker-probe' if probe else 'marker-worker'),f.root/'marker-worker')
    shutil.copy2(BIN/'marker-supervisor',f.root/'supervisor')
    (f.root/'marker-worker').chmod(0o555)
    (f.root/'supervisor').chmod(0o555)
    if probe:
        (f.root/'worker.probe').write_bytes(probe.encode())
    return uid


@contextlib.contextmanager
def launcher(f,leaf,trace=False):
    args=['strace','-ff','-qq','-o','sandbox.trace','-e','trace=socket,connect,openat,symlink,unlink,rename,fork,clone,execve'] if trace else []
    p=subprocess.Popen([*args,'./supervisor',leaf],cwd=f.root,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
    try:
        label,pid=line(p).split()
        assert label=='SupervisorReady' and os.path.samefile(f'/proc/{pid}/exe',f.root/'supervisor')
        p.service_pid=int(pid)
        yield p
    finally:
        if p.poll() is None: p.kill()
        p.wait(timeout=5)


def feasibility(case):
    with fixture() as (f,genesis,_), group() as leaf:
        uid=install(f,genesis,'t' if case=='enclosing' else None)
        with launcher(f,leaf) as sup:
            from test_custody_denial import as_user
            def unauthorized():
                with socket.socket(socket.AF_UNIX,socket.SOCK_SEQPACKET) as s:
                    s.connect(str(f.root/'worker.sock'))
                    assert s.recv(1)==b''
                    return b'refused'
            assert as_user(f.operator,unauthorized)==b'refused' and not (leaf/'cgroup.procs').read_text()
            # The runtime witness has no create primitive. It only checks the reflected packet.
            def reflect():
                with socket.socket(socket.AF_UNIX,socket.SOCK_SEQPACKET) as s:
                    s.settimeout(8)
                    s.connect(str(f.root/'worker.sock'))
                    assert struct.unpack('3i',s.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))[:2]==(sup.pid,0)
                    end=time.clock_gettime_ns(time.CLOCK_BOOTTIME)//1000000+(1000 if case=='enclosing' else 10000)
                    s.send(LE(end))
                    msg,anc,flags,_=s.recvmsg(16,socket.CMSG_SPACE(4))
                    assert len(msg)==16 and len(anc)==1 and not flags
                    pid,registered,until=struct.unpack('<iIq',msg)
                    assert registered==uid and anc[0][:2]==(socket.SOL_SOCKET,socket.SCM_RIGHTS)
                    with socket.socket(fileno=array.array('i',anc[0][2])[0]) as channel:
                        packet=bytes(176)
                        if case=='wrong_pid':
                            sender=os.fork()
                            if not sender:
                                channel.send(packet)
                                os._exit(0)
                            assert os.waitpid(sender,0)==(sender,0)
                        else:
                            channel.send(packet)
                        echo,anc,flags,_=channel.recvmsg(200,socket.CMSG_SPACE(12))
                        if case=='clean':
                            assert echo==packet and not flags and len(anc)==1
                            assert struct.unpack('3i',anc[0][2])==(pid,uid,uid)
                            channel.send(b'\x01')
                        else:
                            assert echo==b''
                            if case=='enclosing': assert until==end
                    assert s.recv(1)==bytes([{'clean':1,'enclosing':2,'wrong_pid':5}[case]])
                    return json.dumps([pid,registered,until]).encode()
            attested=json.loads(as_user(f.runtime,reflect))
            evidence=sup.stdout.read().decode()
            assert sup.wait(timeout=10)==(0 if case=='clean' else 1) and 'populated_empty=1' in evidence
            assert 'fds=0,1,2' in evidence and not list((f.root/'attempts').iterdir())
            print(evidence, 'worker_feasibility',case,attested,flush=True)



@contextlib.contextmanager
def endpoints(f):
    name='wb'+uuid.uuid4().hex[:8]
    def ip(*args):
        subprocess.run(['ip',*args],check=True)
    with contextlib.ExitStack() as stack:
        ip('netns','add',name)
        stack.callback(ip,'netns','del',name)
        ip('link','add',name,'type','veth','peer','name',name+'p')
        stack.callback(ip,'link','del',name)
        ip('link','set',name+'p','netns',name)
        ip('addr','add','192.0.2.1/30','dev',name)
        ip('link','set',name,'up')
        ip('-n',name,'addr','add','192.0.2.2/30','dev',name+'p')
        ip('-n',name,'link','set',name+'p','up')
        listener=stack.enter_context(subprocess.Popen(['ip','netns','exec',name,'python3','-uc',
            'import socket; s=socket.create_server(("192.0.2.2",39491)); print("ready"); s.accept(); import time; time.sleep(30)'],stdout=subprocess.PIPE))
        stack.callback(listener.kill)
        assert listener.stdout.readline()==b'ready\n'
        local=stack.enter_context(socket.socket(socket.AF_UNIX,socket.SOCK_STREAM))
        local.bind(str(f.root/'probe.sock'))
        (f.root/'probe.sock').chmod(0o777)
        local.listen()
        subprocess.run(['python3','-c','import socket; socket.create_connection(("192.0.2.2",39491)).close(); '
                        's=socket.socket(socket.AF_UNIX); s.connect("probe.sock")'],check=True,**identity(f.root,f.operator))
        assert listener.poll() is None
        yield


def execution(probe,payload,expected,stop,requests,output,*,occupancy=False):
    with fixture() as (f,genesis,_), group() as leaf, contextlib.ExitStack() as stack:
        uid=install(f,genesis,probe)
        shutil.copy2(BIN/'marker-approval',f.root/'review')
        if probe=='s':
            stack.enter_context(endpoints(f))
            area=f.root/'probe-area'
            area.mkdir()
            os.chown(area,uid,uid)
            (area/'protected').write_bytes(b'unchanged')

        sup=stack.enter_context(launcher(f,leaf,trace=probe=='s'))
        def protected():
            return f.rows(),sha(f.db.read_bytes()),(f.root/'data/history').read_bytes(),(f.root/'data/head').read_bytes()
        barrier=probe=='s' or occupancy
        if barrier: os.kill(sup.service_pid,signal.SIGSTOP)
        runtime=stack.enter_context(subprocess.Popen(['./review','execute'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,bufsize=0,**identity(f.root,f.runtime)))
        stack.callback(runtime.kill)
        runtime.stdin.write(payload)
        runtime.stdin.close()
        assert line(runtime)=='AwaitingOperator'
        tracer=stack.enter_context(subprocess.Popen(['strace','-qq','-yy','-o',f.root/'broker.trace',
            '-e','trace=openat,close,fsync','-p',str(runtime.pid)]))
        stack.callback(tracer.terminate)
        until=time.monotonic()+5
        while f'TracerPid:\t{tracer.pid}\n' not in Path(f'/proc/{runtime.pid}/status').read_text():
            assert time.monotonic()<until and tracer.poll() is None
            time.sleep(.01)
        proposal=f.query('SELECT canonical_event FROM events WHERE sequence=?',(LE(3),))[0][0]
        approved=subprocess.run(['./review','decide'],input=b'approve\n',capture_output=True,timeout=15,**identity(f.root,f.operator))
        assert approved.returncode==0 and b'Permitted' in approved.stdout
        assert binding(proposal)[1].hex().encode() in approved.stdout
        assert f'Length {len(payload)} SHA256 {sha(payload).hex()}'.encode() in approved.stdout
        assert line(runtime)=='Permitted LiveGrant true'
        handoff=line(runtime)
        assert handoff.startswith(f'BrokerHandoff {STORE.hex()} 1 6 ')
        if barrier:
            assert f.verify()[3:5]==(b'',14) and not (leaf/'cgroup.procs').read_text()
            with f.db.open('rb') as independent:
                fcntl.flock(independent,fcntl.LOCK_EX|fcntl.LOCK_NB)
                baseline=protected()
            os.kill(sup.service_pid,signal.SIGCONT)
        profile=line(sup)
        assert f'uid={uid} group={leaf} fds=0,1,2 memory=33554432 swap=0 pids=1' in profile,profile
        fields=dict(word.split('=',1) for word in profile.split()[1:])
        assert int(fields['until'])-int(fields['start'])==5000
        if probe=='t':
            with f.db.open('rb') as independent:
                fcntl.flock(independent,fcntl.LOCK_EX|fcntl.LOCK_NB)
                assert (leaf/'cgroup.procs').read_text().strip()==fields['worker']
                for pid in (runtime.pid,int(fields['supervisor'])):
                    assert leaf.name not in Path(f'/proc/{pid}/cgroup').read_text()
        status=line(sup)
        assert sup.wait(timeout=10)==(0 if stop==1 else 1),status
        assert f'reaped=1 populated_empty=1 output={output} result={stop} ' in status,status
        elapsed=int(status.split('elapsed=')[1])
        if probe=='t': assert elapsed>=5000
        assert (leaf/'cgroup.procs').read_text()=='' and 'populated 0\n' in (leaf/'cgroup.events').read_text()
        memory={k:int(v) for k,v in (row.split() for row in (leaf/'memory.events.local').read_text().splitlines())}
        if probe=='m': assert memory['max']>0 and memory['oom']>0 and memory['oom_kill']==1
        report=runtime.stdout.read().decode()
        error=runtime.stderr.read()
        success=expected==1 and stop==1
        assert runtime.wait(timeout=10)==(0 if success else 1),(report,error,status)
        assert f'effect={expected} writer_closed=1 requests={requests} stop={stop}' in report,report
        assert ('Threshold WorkerStopped' if success else 'Threshold ExecutionUncertain') in report
        assert tracer.wait(timeout=5)==0
        trace=(f.root/'broker.trace').read_text()
        directory,=(f.root/'attempts').iterdir()
        marker=directory/'marker'
        created=[s for s in trace.splitlines() if '"marker", O_WRONLY|O_CREAT|O_EXCL' in s]
        assert len(created)==int(expected==1),created
        if expected==1:
            assert marker.is_file() and not marker.is_symlink() and marker.read_bytes()==payload
            descriptor=created[0].split(' = ')[-1]
            assert f'<{marker}>' in descriptor and any(s.startswith(f'close({descriptor})') and s.endswith('= 0') for s in trace.splitlines())
        else: assert not marker.exists()
        if probe=='z': assert 'offered_bytes=4097' in report
        if occupancy:
            before=marker.stat(),marker.read_bytes()
            utility=shutil.copy2(BIN/'occupancy-probe',f.root/'occupancy')
            open_trace=f.root/'journal/occupied.trace'
            attempt=subprocess.run(['strace','-qq','-o',open_trace,'-e','trace=openat',utility,directory],
                                   capture_output=True,check=True,**identity(f.root,f.runtime))
            assert any('"marker", O_WRONLY|O_CREAT|O_EXCL' in s and 'EEXIST' in s for s in open_trace.read_text().splitlines())
            assert attempt.stdout==b'ExclusiveResult 2\n' and os.path.samestat(before[0],marker.stat()) and before[1]==marker.read_bytes()
        if probe=='t':
            utility=shutil.copy2(BIN/'occupancy-probe',f.root/'expired')
            expired=subprocess.run([utility,directory,'expired'],capture_output=True,check=True,**identity(f.root,f.runtime))
            assert expired.stdout==b'ExclusiveResult 3\n' and not marker.exists()
        if probe=='s':
            denied=Path(f.root/f"sandbox.trace.{fields['worker']}").read_text()
            for operation in ('socket(AF_INET','socket(AF_UNIX','connect(','"probe-area/adjacent"','"journal/active.db"',
                              '"data/history"',f'symlink("../../journal/active.db", "attempts/{directory.name}', 'unlink(','rename(','fork(','execve("/bin/true"'):
                assert any(operation in s and 'EPERM' in s for s in denied.splitlines()),(operation,denied)
            assert (f.root/'probe-area/protected').read_bytes()==b'unchanged'
            assert list((f.root/'probe-area').iterdir())==[f.root/'probe-area/protected']
            assert len([s for s in denied.splitlines() if 'connect(' in s and 'EPERM' in s])==2
        if barrier: assert protected()==baseline
        view=f.verify()
        rows=sorted(f.rows()[0],key=lambda row:int.from_bytes(row[2],'little'))
        assert [row[3][6] for row in rows]==[8,1,11,12,13,14] and view[3:5]==(b'',14)
        assert rows[-1][3][8:40]==view[2][:32]
        if probe in ('o','x'):
            secret=b'SECRET-WB-CANARY'
            artifacts=[approved.stdout,approved.stderr,report.encode(),error,status.encode(),profile.encode(),trace.encode(),
                       (f.root/'data/history').read_bytes(),f.db.read_bytes(),*(row[3] for row in rows)]
            assert all(secret not in b for b in artifacts)
        with server(f,'receipts',2):
            assert f.verify()==view
        print(json.dumps(dict(claim=rows[-1][3][8:40].hex(),attempt=proposal[104:120].hex(),payload_sha256=sha(payload).hex(),
                              oom_kill=memory['oom_kill'],exclusive_errno='EEXIST' if occupancy else None,
                              offered_bytes=4097 if probe=='z' else len(payload),kernel=os.uname().release,worker_case=probe or 'production',bytes=len(payload),effect=expected,stop=stop,requests=requests,
                              tip=14,output_count=output,elapsed=elapsed,closed=True,scope_empty=True,
                              occupancy=occupancy,profile=profile)),flush=True)


def missing_launcher():
    with fixture() as (f,genesis,_):
        install(f,genesis)
        shutil.copy2(BIN/'marker-approval',f.root/'review')
        with subprocess.Popen(['./review','execute'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,bufsize=0,
                              **identity(f.root,f.runtime)) as issuer:
            issuer.stdin.close()
            assert line(issuer)=='AwaitingOperator'
            subprocess.run(['./review','decide'],input=b'approve\n',capture_output=True,check=True,**identity(f.root,f.operator))
            result=issuer.stdout.read()
            assert issuer.wait(timeout=5)==1 and b'BrokerHandoff' in result and b'ExecutionUncertain' in result
        view,rows=f.verify(),f.rows()
        retry=subprocess.run(['./review','execute'],input=b'',capture_output=True,timeout=5,**identity(f.root,f.runtime))
        assert retry.returncode==1 and b'BrokerHandoff' not in retry.stdout and f.rows()==rows and f.verify()==view
        with server(f,'receipts',2):
            directory,=(f.root/'attempts').iterdir()
            assert not list(directory.iterdir())
        print('worker_transfer_failure consumed=true retries=0 marker=absent tip=14',flush=True)


def run():
    hosted='--hosted' in sys.argv
    if hosted:
        try:
            with group(): pass
        except OSError as exc:
            if exc.errno not in (errno.EPERM,errno.EACCES,errno.EROFS,errno.ENOENT): raise
            print('Worker cgroup preflight unavailable:',exc,'; no hosted worker qualification')
            return
    for case in ('clean','wrong_pid','enclosing'): feasibility(case)
    missing_launcher()
    for args in [(None,b'',1,1,1,0),(None,bytes(range(256))*16,1,1,1,0),('s',b'fixed',1,1,1,0),
                 ('o',b'bounded',1,1,1,4096),('x',b'overflow',0,3,0,4097),('m',b'memory',0,4,0,0),
                 ('t',b'timeout',0,2,0,0),('d',b'once',1,1,2,0),('b',b'tool',3,1,1,0),
                 ('i',b'target',3,1,1,0),('p',b'changed',3,1,1,0),('z',b'full',3,1,1,0)]:
        if hosted and args[0]=='s':
            ns='wb-check-'+uuid.uuid4().hex[:8]
            check=subprocess.run(['ip','netns','add',ns],capture_output=True,text=True)
            if check.returncode and 'Operation not permitted' in check.stderr:
                print('Network namespace unavailable; combined confinement probe unqualified:',check.stderr.strip())
                continue
            check.check_returncode()
            subprocess.run(['ip','netns','del',ns],check=True)
        execution(*args,occupancy=args[0] is None and bool(args[1]))


if __name__=='__main__':
    run()
