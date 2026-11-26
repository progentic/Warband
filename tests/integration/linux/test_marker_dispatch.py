"""The post-claim checkpoint and the request presented to the gate have separate oracles."""
import contextlib
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import subprocess
import time

from test_marker_approval import PAYLOAD, binding, cli, identity, line, server
from test_receipt_import import LE, OUT, STORE, emit, fixture, sha


def wait_stop(p):
    until=time.monotonic()+15
    while time.monotonic()<until:
        event=os.waitid(os.P_PID,p.pid,os.WSTOPPED|os.WEXITED|os.WNOHANG)
        if event:
            assert (event.si_pid,event.si_code,event.si_status)==(p.pid,os.CLD_STOPPED,signal.SIGSTOP),event
            return
        time.sleep(.01)
    raise TimeoutError('issuer failed to stop')


@contextlib.contextmanager
def observe_process(f,srv):
    path=f.root/'gate.trace'
    tracer=subprocess.Popen(['strace','-qq','-f','-e','trace=%process,openat','-o',path,'-p',str(srv.pid)])
    try:
        until=time.monotonic()+5
        while not re.search(rf'^TracerPid:\s+{tracer.pid}$',Path(f'/proc/{srv.pid}/status').read_text(),re.M):
            assert tracer.poll() is None and time.monotonic()<until
            time.sleep(.01)
        yield
        assert tracer.wait(timeout=10)==0
        trace=path.read_text()
        assert 'active.db' in trace and not re.search(r'\b(execve(?:at)?|clone3?|v?fork)\(',trace)
        assert not re.search(r'openat\([^\n]*"marker"[^\n]*(?:O_WRONLY|O_RDWR|O_CREAT)',trace)
    finally:
        if tracer.poll() is None:
            tracer.terminate()
            tracer.wait(timeout=5)


def ledger(f,genesis,kinds,seq,tip,pending=False):
    view=f.verify()
    rows=sorted(f.rows()[0],key=lambda x:int.from_bytes(x[2],'little'))
    assert [row[3][6] for row in rows]==kinds
    head=genesis
    for i,(store,ep,key,wire) in enumerate(rows,1):
        ref=STORE+LE(1)+LE(i)
        assert store+ep+key==ref==wire[8:40] and head==wire[-32:]
        digest=sha(b'warband.event.v1\0'+wire[:-32])
        head=sha(b'warband.link.v1\0'+ref+head+digest)
        if i==seq:
            assert view[2]==ref+head
        if i>seq:
            assert view[3]==view[2]+LE(i)+head+digest
    assert view[4]==tip and bool(view[3])==pending
    return [row[3] for row in rows]


def marker_dispatch_case(case,code,expected,reason):
    ordinary=case=='ordinary'
    with fixture() as (f,genesis,_):
        (f.root/'intake.anchor').write_bytes(STORE+LE(1)+LE(0)+genesis+struct.pack('<I',f.custodian))
        (f.root/'approval.ids').write_bytes(struct.pack('<II',f.runtime,f.operator))
        parent=f.root/'attempts'
        parent.mkdir(mode=0o700)
        os.chown(parent,f.runtime,f.runtime)
        normal=OUT/'reconcile/marker-approval'
        proof=OUT/'reconcile/marker-approval-gate-proof'
        binary=normal if ordinary else proof
        exe=shutil.copy2(binary,f.root/'review')
        observer=sha(binary.read_bytes()).hex()
        assert observer!=sha((proof if ordinary else normal).read_bytes()).hex()
        before=[8,1,11,12,13]
        claimed=before+[14]
        with server(f,'gate') as srv, observe_process(f,srv), contextlib.ExitStack() as cleanup:
            proposal=f.query('SELECT canonical_event FROM events WHERE sequence=?',(LE(3),))[0][0]
            assert cli(f,proposal,b'approve')==(0,f'Permitted {STORE.hex()} 1 4')
            assert line(srv)=='Permitted LiveGrant true'
            directory,=parent.iterdir()
            original_dir=directory.stat()
            marker=directory/'marker'
            if not ordinary:
                wait_stop(srv)
                events=ledger(f,genesis,claimed,5,13,True)
                if case=='recover_commit':
                    srv.kill()
                    assert srv.wait(timeout=5)==-signal.SIGKILL
                else:
                    os.kill(srv.pid,signal.SIGCONT)
                    wait_stop(srv)
                    assert ledger(f,genesis,claimed,6,14)==events
                    with server(f,'receipts',2):
                        assert not list(directory.iterdir())
                    held,=[path for path in Path(f'/proc/{srv.pid}/fd').iterdir() if os.readlink(path)==str(directory)]
                    assert os.path.samestat(held.stat(),directory.stat())
                    emit(marker_claim_barrier=case,binary=observer,sequence=6,tip=14,pending=False,consumed=True,
                         projection=[1,2],leaf='absent',device=held.stat().st_dev,inode=held.stat().st_ino)
            else:
                assert srv.wait(timeout=15)==0, srv.stdout.read()
                events=ledger(f,genesis,claimed,6,14)
            permit,claim=events[-2:]
            ref,fp,_,payload_hash=binding(proposal)
            assert permit[56:88]==events[3][8:40] and permit[120]==1
            assert claim[48:56]==struct.pack('<HHI',2,1,112)
            assert claim[56:-32]==permit[8:40]+proposal[104:120]+permit[88:104]+LE(1)+LE(1)+fp
            assert not marker.exists()
            if case=='restart':
                srv.kill()
                assert srv.wait(timeout=5)==-signal.SIGKILL
            if case in ('restart','recover_commit'):
                shutil.copy2(normal,exe)
                with server(f,'receipts',1 if case=='recover_commit' else 2) as fresh:
                    assert cli(f,proposal,b'approve')==(0,f'Recorded {STORE.hex()} 1 4')
                    assert line(fresh)=='Recorded LiveGrant false' and fresh.wait(timeout=5)==0
                with server(f,'receipts',2):
                    assert ledger(f,genesis,claimed,6,14)==events
                repeat=subprocess.run([exe,'gate'],input=PAYLOAD,capture_output=True,timeout=10,**identity(f.root,f.runtime))
                assert repeat.returncode==1 and b'BrokerHandoff' not in repeat.stdout and ledger(f,genesis,claimed,6,14)==events
                assert not list(directory.iterdir())
                emit(marker_dispatch=case,tip=14,claim=claim[8:40].hex(),fresh_grant=False)
                return
            offered=bytearray(proposal)
            task,control=1,2
            if code==1: offered[187]^=1
            if code==2: offered[88]^=1
            if code==4: task-=1
            if code==5: control-=1
            digest=sha(b'warband.marker.dispatch.v1\0'+claim[8:40]+offered+fp+payload_hash+LE(task)+LE(control))
            if case=='replacement':
                directory.rename(f.root/'held-original')
                directory.mkdir(mode=0o700)
                os.chown(directory,f.runtime,f.runtime)
            if case in ('occupied','recover_refusal'):
                marker.write_bytes(b'pre-existing sentinel\n')
                saved=marker.stat(),marker.read_bytes()
            if case=='unconfirmed':
                holder=cleanup.enter_context(subprocess.Popen(['python3','-uc',
                    'import sqlite3; c=sqlite3.connect("journal/active.db"); c.execute("BEGIN IMMEDIATE"); print("locked"); input()'],
                    stdin=subprocess.PIPE,stdout=subprocess.PIPE,**identity(f.root,f.runtime)))
                cleanup.callback(holder.kill)
                assert holder.stdout.readline()==b'locked\n'
            if not ordinary:
                (f.root/'gate-proof-input').write_bytes(bytes([code]))
                os.kill(srv.pid,signal.SIGCONT)
            if reason and case!='unconfirmed':
                wait_stop(srv)
                pending=ledger(f,genesis,claimed+[8],6,15,True)
                assert pending[-1][56:-32]==struct.pack('<BHB',3,reason,1)+claim[8:40]+digest
                if case=='recover_refusal':
                    srv.kill()
                    assert srv.wait(timeout=5)==-signal.SIGKILL and not srv.stdout.read()
                    shutil.copy2(normal,exe)
                    with server(f,'receipts',2) as fresh:
                        assert cli(f,proposal,b'approve')==(0,f'Recorded {STORE.hex()} 1 4')
                        assert line(fresh)=='Recorded LiveGrant false' and fresh.wait(timeout=5)==0
                    assert ledger(f,genesis,claimed+[8],7,16)==pending
                    assert os.path.samestat(saved[0],marker.stat()) and marker.read_bytes()==saved[1]
                    emit(marker_dispatch=case,tip=16,claim=claim[8:40].hex(),fresh_grant=False,leaf='preserved sentinel')
                    return
                os.kill(srv.pid,signal.SIGCONT)
            output=srv.stdout.read().decode().splitlines()
            rc=srv.wait(timeout=10)
            if expected=='Eligible':
                handoff=f'BrokerHandoff {STORE.hex()} 1 6 {proposal[104:120].hex()} {digest.hex()}'
                assert (rc,output)==(0,[handoff]+([] if ordinary else ['SecondEvaluation NoLiveGrant'])+['Threshold Eligible']),output
                assert ledger(f,genesis,claimed,6,14)==events
            elif case=='unconfirmed':
                assert (rc,output)==(1,['Threshold RefusalUnconfirmed']),output
                assert ledger(f,genesis,claimed,6,15,True)==events
            else:
                assert (rc,output)==(1,['Threshold '+expected]),output
                final=ledger(f,genesis,claimed+[8],7,16)
                assert final[:-1]==events and final[-1][48:56]==struct.pack('<HHI',2,1,68)
                assert final[-1][56:-32]==struct.pack('<BHB',3,reason,1)+claim[8:40]+digest
            if case in ('occupied','recover_refusal'):
                assert os.path.samestat(saved[0],marker.stat()) and saved[1]==marker.read_bytes()
            else:
                assert not list(directory.iterdir())
                if case=='replacement':
                    assert not os.path.samestat(original_dir,directory.stat())
                    assert os.path.samestat(original_dir,(f.root/'held-original').stat())
                    assert not list((f.root/'held-original').iterdir())
            if case!='replacement':
                assert os.path.samestat(original_dir,directory.stat())
        if case=='unconfirmed':
            halted=subprocess.run([exe,'receipts'],capture_output=True,timeout=10,**identity(f.root,f.runtime))
            assert halted.returncode==1 and b'AwaitingOperator' not in halted.stdout
            assert f.verify()[3][:72]==f.verify()[2]+LE(7)
        else:
            with server(f,'receipts',2):
                pass
        emit(marker_dispatch=case,binary=observer,gate=expected,claim=claim[8:40].hex(),request_digest=digest.hex(),
             advertised_fingerprint=fp.hex(),offered_fingerprint=binding(offered)[1].hex(),
             advertised_payload_digest=payload_hash.hex(),offered_payload_digest=binding(offered)[3].hex(),
             confirmed_tip=f.verify()[4],comparison_reason=reason if case!='unconfirmed' else None,offered_task=task,offered_control=control,
             policy_observation='supplied 1' if code==3 else 'registered 2',projection=[1,2],consumed=True,handoffs=int(expected=='Eligible'),worker_invocations=0,
             leaf='preserved sentinel' if case=='occupied' else 'absent')


def run():
    for args in [
        ('ordinary',0,'Eligible',0),('paired',0,'Eligible',0),('payload',1,'PayloadMismatch',9),
        ('fingerprint',2,'FingerprintMismatch',9),('supplied_policy',3,'PolicyMismatch',2),
        ('task',4,'TaskMismatch',4),('control',5,'ControlMismatch',4),('replacement',0,'DirectoryMismatch',3),
        ('withdrawn',6,'DirectoryLost',9),('occupied',0,'Occupied',9),('restart',0,None,0),
        ('recover_commit',0,None,0),('recover_refusal',0,None,9),('unconfirmed',1,'RefusalUnconfirmed',9),
    ]:
        marker_dispatch_case(*args)
