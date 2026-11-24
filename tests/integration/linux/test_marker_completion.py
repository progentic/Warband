"""Qualify live marker observation, independent evaluation and atomic acceptance."""
import contextlib
import errno
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import time

from test_receipt_import import LE, STORE, fixture, sha
from test_marker_approval import PAYLOAD, binding, cli, identity, line
from test_marker_worker import BIN, group, install, launcher


def canonical(f):
    return [row[3] for row in sorted(f.rows()[0],key=lambda row:int.from_bytes(row[2],'little'))]


def accepted_rows(f):
    return f.query('SELECT attempt_id,transition_id,sequence FROM accepted_attempts')


def install_case(f,genesis,mode=None,binary='marker-approval'):
    accept=shutil.copy2(BIN/'accept-noop',f.root/'accept')
    provision=subprocess.run([accept,f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1','provision-index'],
                             capture_output=True,text=True,timeout=20,**identity(f.root,f.runtime))
    assert provision.returncode==0 and provision.stdout.split()==['IndexVerified'],provision
    install(f,genesis)
    shutil.copy2(BIN/binary,f.root/'review')
    if mode:
        probe=f.root/'completion.probe'
        probe.write_bytes(mode.encode())
        probe.chmod(0o444)
        st=probe.stat()
        assert st.st_uid==0 and st.st_mode&0o777==0o444 and st.st_size==1
    if mode=='u':
        shutil.copy2(BIN/'marker-supervisor-proof',f.root/'supervisor')


def finish(f,binary='marker-approval'):
    shutil.copy2(BIN/binary,f.root/'review')
    return subprocess.run(['./review','finalize'],capture_output=True,timeout=20,**identity(f.root,f.runtime))


def assert_events(f,mode,payload=PAYLOAD):
    rows=canonical(f)
    accepted=mode in (None,'l')
    assert [row[6] for row in rows]==([8,1,11,12,13,14,15,16,17] if accepted else [8,1,11,12,13,14,15,16])
    observation,evaluation=rows[6:8]
    delivery={'l':2}.get(mode,1)
    stopped=mode!='u'
    control=mode not in ('u','d')
    entry={'a':1,'u':0,'d':0}.get(mode,2)
    expected_bytes={'p':payload[:-1],'c':bytes([payload[0]^1])+payload[1:]}.get(mode,payload)
    assert (observation[104],observation[105],observation[106],observation[107])==(delivery,stopped,control,entry),(
        mode,(observation[104],observation[105],observation[106],observation[107]),(delivery,stopped,control,entry))
    if entry==2:
        assert struct.unpack_from('<Q',observation,108)[0]==len(expected_bytes)
        assert observation[116:148]==sha(expected_bytes)
    else:
        assert observation[108:148]==bytes(40)
    assert evaluation[56:88]==observation[8:40] and evaluation[88:120]==observation[56:88]
    assert evaluation[120:152]==sha(b'warband.event.v1\0'+observation[:-32])
    verdict=1 if accepted or mode in ('v','r') else (2 if mode=='a' else 3)
    assert evaluation[154]==verdict
    assert f.verify()[3:5]==(b'',20 if accepted else 18)
    index=accepted_rows(f)
    if accepted:
        event=rows[8]
        assert event[56:88]==evaluation[8:40] and event[88:120]==observation[56:88]
        assert struct.unpack_from('<QQQ',event,136)==(1,2,2) and event[160]==2
        assert len(index)==1 and index[0][1]==event[120:136] and index[0][2]==LE(9)
    else:
        assert index==[]
    return rows,expected_bytes


def completion_case(mode=None):
    with fixture() as (f,genesis,_), group() as leaf:
        binary='marker-approval-completion-proof' if mode else 'marker-approval'
        install_case(f,genesis,mode,binary)
        with launcher(f,leaf) as sup:
            runtime=subprocess.Popen(['./review','complete'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,bufsize=0,**identity(f.root,f.runtime))
            try:
                runtime.stdin.write(PAYLOAD)
                runtime.stdin.close()
                assert line(runtime)=='AwaitingOperator'
                proposal=f.query('SELECT canonical_event FROM events WHERE sequence=?',(LE(3),))[0][0]
                assert cli(f,proposal,b'approve')==(0,f'Permitted {STORE.hex()} 1 4')
                assert line(runtime)=='Permitted LiveGrant true'
                output=runtime.stdout.read().decode()
                error=runtime.stderr.read()
                expected_rc=1 if mode in ('v','r') else 0
                assert runtime.wait(timeout=20)==expected_rc,(output,error,f.verify(),[row[6] for row in canonical(f)],accepted_rows(f))
            finally:
                if runtime.poll() is None: runtime.kill()
            supervisor=sup.stdout.read().decode()
            assert sup.wait(timeout=10)==(1 if mode in ('l','u') else 0),supervisor
        rows,expected=assert_events(f,mode)
        directory,=(f.root/'attempts').iterdir()
        marker=directory/'marker'
        if mode=='a': assert not marker.exists()
        else: assert marker.read_bytes()==expected
        expected_result={'v':'AcceptanceVersionsInvalid','r':'AcceptanceReferenceInvalid'}.get(
            mode,'Completed' if mode in (None,'l') else ('CompletionIncomplete' if mode=='a' else 'CompletionReconciliation'))
        assert f'Threshold {expected_result}' in output,output
        if mode in (None,'l'): assert 'AcceptancePreflight None' in output
        if mode=='v': assert 'AcceptancePreflight VersionsInvalid' in output
        if mode=='r': assert 'AcceptancePreflight ReferenceInvalid' in output
        assert output.count('BrokerHandoff')==1 and 'ObservationRef' in output and 'EvaluationRef' in output
        if mode in (None,'l'):
            before=f.rows(),f.verify(),accepted_rows(f)
            for _ in range(2):
                duplicate=finish(f)
                assert duplicate.returncode==0 and f'CompletionRef {STORE.hex()} 1 9'.encode() in duplicate.stdout
                assert b'Completion Recorded' in duplicate.stdout and (f.rows(),f.verify(),accepted_rows(f))==before
        frozen=f.rows(),f.verify(),accepted_rows(f)
        retry=subprocess.run(['./review','execute'],input=PAYLOAD,capture_output=True,timeout=10,**identity(f.root,f.runtime))
        assert retry.returncode==1 and b'BrokerHandoff' not in retry.stdout and (f.rows(),f.verify(),accepted_rows(f))==frozen
        print(dict(completion=mode or 'reply',tip=f.verify()[4],kinds=[row[6] for row in rows],
                   delivery=rows[6][104],verdict=rows[7][154],accepted=bool(accepted_rows(f))),flush=True)


def wait_stopped(proc):
    until=time.monotonic()+15
    while time.monotonic()<until:
        event=os.waitid(os.P_PID,proc.pid,os.WSTOPPED|os.WEXITED|os.WNOHANG|os.WNOWAIT)
        if event:
            assert event.si_code==os.CLD_STOPPED and event.si_status==signal.SIGSTOP,event
            return
        time.sleep(.01)
    raise TimeoutError('completion boundary stop')


def interrupted(edge):
    with fixture() as (f,genesis,_), group() as leaf:
        install_case(f,genesis,binary=f'marker-approval-completion-{edge}')
        with launcher(f,leaf) as sup:
            runtime=subprocess.Popen(['./review','complete'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,bufsize=0,**identity(f.root,f.runtime))
            runtime.stdin.write(PAYLOAD); runtime.stdin.close()
            assert line(runtime)=='AwaitingOperator'
            proposal=f.query('SELECT canonical_event FROM events WHERE sequence=?',(LE(3),))[0][0]
            assert cli(f,proposal,b'approve')[0]==0
            assert line(runtime)=='Permitted LiveGrant true'
            wait_stopped(runtime)
            runtime.kill(); assert runtime.wait(timeout=5)==-signal.SIGKILL
            sup.wait(timeout=10)
        before=f.verify()
        assert before[3] and before[4]=={15:15,16:17,17:19}[edge]
        assert len(canonical(f))=={15:7,16:8,17:9}[edge]
        recovered=finish(f)
        assert recovered.returncode==0,recovered
        assert b'Completion Completed' in recovered.stdout or b'Completion Recorded' in recovered.stdout
        rows=canonical(f)
        assert [row[6] for row in rows]==[8,1,11,12,13,14,15,16,17]
        assert f.verify()[3:5]==(b'',20) and len(accepted_rows(f))==1
        frozen=f.rows(),f.verify(),accepted_rows(f)
        again=finish(f)
        assert again.returncode==0 and b'Completion Recorded' in again.stdout and (f.rows(),f.verify(),accepted_rows(f))==frozen
        print(dict(completion_crash=edge,pending_tip=before[4],confirmed_tip=20,accepted_once=True),flush=True)


def stage_evaluation(f,leaf):
    shutil.copy2(BIN/'marker-approval-accept-barrier',f.root/'review')
    with launcher(f,leaf) as sup:
        runtime=subprocess.Popen(['./review','complete'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,bufsize=0,**identity(f.root,f.runtime))
        runtime.stdin.write(PAYLOAD); runtime.stdin.close()
        assert line(runtime)=='AwaitingOperator'
        proposal=f.query('SELECT canonical_event FROM events WHERE sequence=?',(LE(3),))[0][0]
        assert cli(f,proposal,b'approve')[0]==0
        assert line(runtime)=='Permitted LiveGrant true'
        wait_stopped(runtime)
        runtime.kill(); assert runtime.wait(timeout=5)==-signal.SIGKILL
        assert sup.wait(timeout=10)==0
    assert [row[6] for row in canonical(f)]==[8,1,11,12,13,14,15,16]
    assert f.verify()[3:5]==(b'',18) and accepted_rows(f)==[]


def acceptance_fault(stage):
    with fixture() as (f,genesis,_), group() as leaf:
        install_case(f,genesis)
        stage_evaluation(f,leaf)
        shutil.copy2(BIN/f'marker-approval-accept-{stage}',f.root/'review')
        actor=subprocess.Popen(['./review','finalize'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                               bufsize=0,**identity(f.root,f.runtime))
        wait_stopped(actor)
        actor.kill(); assert actor.wait(timeout=5)==-signal.SIGKILL
        pending=f.verify()
        assert pending[3] and pending[4]==19
        rows=canonical(f)
        if stage=='insert':
            assert len(rows)==8 and accepted_rows(f)==[]
            frozen=f.rows(),f.verify(),accepted_rows(f)
            halted=finish(f)
            assert halted.returncode==1 and b'Completion CompletionUnconfirmed' in halted.stdout
            assert (f.rows(),f.verify(),accepted_rows(f))==frozen
        else:
            assert len(rows)==9 and len(accepted_rows(f))==1
            recovered=finish(f)
            assert recovered.returncode==0 and b'Completion Recorded' in recovered.stdout
            assert f.verify()[3:5]==(b'',20) and len(canonical(f))==9
        print(dict(acceptance_fault=stage,pending_tip=19,events=len(rows),index=len(accepted_rows(f))),flush=True)


def acceptance_contention():
    with fixture() as (f,genesis,_), group() as leaf:
        install_case(f,genesis)
        stage_evaluation(f,leaf)
        shutil.copy2(BIN/'marker-approval-accept-barrier',f.root/'accept-first')
        shutil.copy2(BIN/'marker-approval',f.root/'review')
        first=subprocess.Popen(['./accept-first','finalize'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                               bufsize=0,**identity(f.root,f.runtime))
        wait_stopped(first)
        frozen=f.rows(),f.verify(),accepted_rows(f)
        refused=subprocess.run(['./review','finalize'],capture_output=True,timeout=20,**identity(f.root,f.runtime))
        assert refused.returncode==1 and b'Completion CompletionUnconfirmed' in refused.stdout
        assert (f.rows(),f.verify(),accepted_rows(f))==frozen
        first.send_signal(signal.SIGCONT)
        stdout,stderr=first.communicate(timeout=20)
        assert first.returncode==0 and b'AcceptancePreflight None' in stdout and b'Completion Completed' in stdout,(stdout,stderr)
        settled=f.rows(),f.verify(),accepted_rows(f)
        duplicate=subprocess.run(['./review','finalize'],capture_output=True,timeout=20,**identity(f.root,f.runtime))
        assert duplicate.returncode==0 and b'Completion Recorded' in duplicate.stdout
        assert (f.rows(),f.verify(),accepted_rows(f))==settled and settled[1][4]==20 and len(settled[2])==1
        print(dict(acceptance_contention='one accepted',refused_while_locked=True,duplicate='original'),flush=True)


def run():
    if '--hosted' in sys.argv:
        try:
            with group(): pass
        except OSError as exc:
            if exc.errno not in (errno.EPERM,errno.EACCES,errno.EROFS,errno.ENOENT): raise
            print('Completion cgroup preflight unavailable:',exc,'; no hosted completion qualification')
            return
    for mode in (None,'l','a','p','c','u','d','v','r'):
        completion_case(mode)
    for edge in (15,16,17):
        interrupted(edge)
    for stage in ('insert','wal'):
        acceptance_fault(stage)
    acceptance_contention()


if __name__=='__main__':
    run()
