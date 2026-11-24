"""Real writer, custodian, kernel xattr and restart evidence for ADR-0011."""
import contextlib
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import signal
import sqlite3
import subprocess
import tempfile
import time
from unittest.mock import patch

import test_custody_denial
import test_receipt_import
import test_model_request as model
from test_model_request import actor, candidate, command, finish_admission, issued, request_store
from test_receipt_import import LE, OUT, STORE, hold_reader


def snapshot(f):
    status, _, cp, pending, tip, _ = f.verify()
    assert status == 0
    def records(sql):
        return [[v.hex() if isinstance(v, bytes) else v for v in row] for row in f.query(sql)]
    dirs = []
    for directory in sorted((f.root/'attempts').iterdir()):
        dirs.append(dict(name=directory.name, inode=directory.stat().st_ino, dev=directory.stat().st_dev,
                         files=sorted(p.name for p in directory.iterdir()),
                         attrs={k: os.getxattr(directory,k).hex() for k in sorted(os.listxattr(directory))}))
    return dict(checkpoint=cp.hex(), pledge=pending.hex(), tip=tip, dirs=dirs,
                events=records('SELECT canonical_event FROM events ORDER BY sequence'),
                requests=records('SELECT * FROM request_facts ORDER BY sequence'),
                consumed=records('SELECT * FROM consumed_requests ORDER BY sequence'))


def evidence(label, **fields):
    print(json.dumps(dict(model_request_case=label, **fields), sort_keys=True), flush=True)


def assert_pair(state, count):
    proposals = [w for (w,) in state['events'] if bytes.fromhex(w)[6] == 11]
    assert (len(proposals), len(state['consumed'])) == (count, count), state
    for (wire,) in state['events']:
        assert bytes.fromhex(wire)[6] in (1, 11, 18, 19)


@contextlib.contextmanager
def process(f, edge='', proof=True):
    binary = './model-request'
    if proof:
        binary = './model-request-proof'
        shutil.copy2(OUT/'reconcile/model-request-proof', f.root/binary)
    p = subprocess.Popen([binary,'issue-abc'], **actor(f), env=dict(os.environ,WB_REQUEST_EDGE=edge),
                         stdout=subprocess.PIPE,stderr=subprocess.PIPE,stdin=subprocess.PIPE,bufsize=0)
    try:
        yield p
    finally:
        if p.poll() is None:
            p.kill()
        p.wait(timeout=10)


def read_id(p):
    assert select.select([p.stdout], [], [], 20)[0], 'issuance timed out'
    line = p.stdout.readline().split()
    assert len(line)==2 and line[0]==b'Issued', (p.poll(),line)
    return bytes.fromhex(line[1].decode())


def wait_stopped(p):
    until = time.monotonic()+20
    status = Path(f'/proc/{p.pid}/status')
    while p.poll() is None and time.monotonic()<until:
        if any(line.startswith('State:') and 'T (stopped)' in line for line in status.read_text().splitlines()):
            return
        time.sleep(.02)
    raise AssertionError(('missing proof stop',p.poll()))


def send_candidate(p, rid, op=b'a'):
    p.stdin.write(op + candidate(rid))
    p.stdin.close()
    p.stdin = None


def crash_case(kind, edge):
    label = f'{kind:02}.{edge}'
    with request_store() as f:
        command(f,'provision',['Ready'])
        before = snapshot(f)
        with process(f,label) as p:
            if kind != 18:
                rid = read_id(p)
                if kind==19:
                    p.stdin.write(b'c')
                else:
                    send_candidate(p,rid)
            wait_stopped(p)
            p.kill()
            assert p.wait(timeout=10)==-signal.SIGKILL
        interrupted = snapshot(f)
        if kind==18 and edge=='before-prepare':
            expected = ['Ready']
        elif kind==19 and edge=='before-prepare':
            expected = ['Expired','Ready']
        elif kind in (18,19) and edge in ('committed','confirmed'):
            expected = (['Recorded'] if edge=='committed' else []) + (['Expired'] if kind==18 else []) + ['Ready']
        elif kind==11 and edge in ('time-synced','confirmed'):
            expected = (['Recorded'] if edge=='time-synced' else []) + ['Ready']
        else:
            expected = ['Reconciliation']
        command(f,'recover',expected, int(expected==['Reconciliation']))
        after=snapshot(f)
        assert_pair(after, int(kind==11 and edge in ('committed','time-synced','confirmed')))
        if expected==['Reconciliation']:
            assert interrupted==after
        if kind==11 and edge in ('time-synced','confirmed'):
            assert after['tip']==7 and not after['pledge'] and len(after['events'])==3
        if kind==11 and edge in ('xattr-set','provenance-synced','before-prepare','prepared'):
            assert len(after['dirs'])==1 and not after['dirs'][0]['files']
        evidence(label,before=before,interrupted=interrupted,after=after,recovery=expected)


def sql_failure(edge):
    with request_store() as f:
        command(f,'provision',['Ready'])
        with process(f,'11.'+edge) as p:
            rid=read_id(p)
            send_candidate(p,rid)
            output,err=p.communicate(timeout=20)
            assert p.returncode==1 and output==b'Reconciliation\n', (output,err)
        state=snapshot(f)
        assert_pair(state,0)
        assert state['tip']==6 and state['pledge']
        command(f,'recover',['Reconciliation'],1)
        assert state==snapshot(f)
        evidence(edge,after=state,recovery='Reconciliation')


def late_commit():
    with request_store() as f:
        command(f,'provision',['Ready'])
        with process(f,'11.inside-commit') as p:
            rid=read_id(p)
            deadline=int.from_bytes(f.query('SELECT wire FROM request_facts')[0][0][152:160],'little')
            send_candidate(p,rid)
            wait_stopped(p)
            now_ms = lambda: time.clock_gettime_ns(time.CLOCK_BOOTTIME)//1_000_000
            assert now_ms()<deadline
            time.sleep((deadline-now_ms())/1000+.05)
            assert now_ms()>=deadline
            p.send_signal(signal.SIGCONT)
            out,err=p.communicate(timeout=15)
            assert (p.returncode,out)==(1,b'Reconciliation\n'),err
        state=snapshot(f)
        assert_pair(state,1)
        assert state['tip']==6 and state['pledge'] and 'user.warband.commit.v1' not in state['dirs'][0]['attrs']
        command(f,'recover',['Reconciliation'],1)
        assert state==snapshot(f)
        evidence('commit-crosses-deadline',after=state,recovery='Reconciliation',deadline_ms=deadline)


def duplicate_race():
    with request_store() as f:
        command(f,'provision',['Ready'])
        with process(f) as p:
            rid=read_id(p)
            send_candidate(p,rid,b'r')
            out,err=p.communicate(timeout=20)
            verdicts=sorted(out.splitlines())
            assert p.returncode==0 and verdicts in ([b'Admitted',b'Busy'],[b'Admitted',b'Consumed']), (out,err)
        before=snapshot(f)
        retry=subprocess.run(['./model-request','retry'],input=rid.hex().encode()+candidate(rid),capture_output=True,**actor(f),timeout=15)
        assert retry.returncode==1 and retry.stdout==b'Consumed\n'
        assert_pair(before,1)
        assert before['tip']==7 and before==snapshot(f)
        evidence('concurrent-delivery',outcomes=out.decode().splitlines(),fresh='Consumed',after=before)


def retarget_and_rewrite():
    # A second genuine enrollment gives a valid but foreign full Ref, F and digest.
    other = bytes([9])*16
    with patch.object(test_custody_denial,'STORE',other), patch.object(test_receipt_import,'STORE',other), \
         patch.object(model,'ENROLL',other+model.ENROLL[16:]), request_store() as donor:
        command(donor,'provision',['Ready'])
        with issued(donor) as (p,rid):
            finish_admission(p,rid)
        target,=donor.query('SELECT store_id,epoch,sequence,event_digest,fingerprint FROM consumed_requests')
        assert target[0]==other
    for case in ('retarget','rollback','deleted-row','row-without-provenance','bad_fields'):
        with request_store() as f, tempfile.TemporaryDirectory() as directory:
            command(f,'provision',['Ready'])
            with issued(f) as (p,rid):
                backup=Path(directory)/'before.db'
                with contextlib.closing(sqlite3.connect(f.db)) as source, contextlib.closing(sqlite3.connect(backup)) as dest:
                    source.backup(dest)
                finish_admission(p,rid)
            if case=='rollback':
                with contextlib.closing(sqlite3.connect(backup)) as source, contextlib.closing(sqlite3.connect(f.db)) as dest:
                    source.backup(dest)
            elif case=='retarget':
                f.query('UPDATE consumed_requests SET store_id=?,epoch=?,sequence=?,event_digest=?,fingerprint=?', target)
            elif case=='deleted-row':
                f.query('DELETE FROM consumed_requests')
            elif case=='row-without-provenance':
                attempt, = (f.root/'attempts').iterdir()
                os.removexattr(attempt,'user.warband.request.v1')
            else:
                for field in ('store_id','request_id','epoch','sequence','catalog_id','payload_digest','event_digest','fingerprint'):
                    original,=f.query(f'SELECT {field} FROM consumed_requests')[0]
                    changed=bytes([original[0]^128])+original[1:]
                    f.query(f'UPDATE consumed_requests SET {field}=?',(changed,))
                    before=snapshot(f)
                    command(f,'recover',['Reconciliation'],1)
                    assert before==snapshot(f)
                    evidence('altered-'+field,after=before,recovery='Reconciliation')
                    f.query(f'UPDATE consumed_requests SET {field}=?',(original,))
                continue
            before=snapshot(f)
            command(f,'recover',['Reconciliation'],1)
            assert before==snapshot(f)
            evidence(case,after=before,recovery='Reconciliation')


def early_denials():
    with request_store() as f:
        command(f,'provision',['Ready'])
        rid=bytes(range(16))
        for case in ('unknown','foreign-session','expired','wrong-candidate'):
            if case in ('foreign-session','expired'):
                with issued(f) as (p,rid):
                    if case=='expired':
                        p.communicate(b'c',timeout=10)
                expected=b'Reconciliation\n' if case=='foreign-session' else b'Expired\n'
            elif case=='wrong-candidate':
                with issued(f) as (p,rid):
                    output,err=p.communicate(b'a'+candidate(bytes(16)),timeout=15)
                    assert (p.returncode,output)==(1,b'CandidateRejected\n'),err
                expected=output
            else:
                expected=b'Unknown\n'
            before=snapshot(f)
            if case!='wrong-candidate':
                result=subprocess.run(['./model-request','retry'],input=rid.hex().encode()+candidate(rid),
                                      capture_output=True,**actor(f),timeout=15)
                assert (result.returncode,result.stdout)==(1,expected)
            assert before==snapshot(f) and not before['dirs'] and not before['pledge']
            assert all(bytes.fromhex(w)[6] in (18,19) for (w,) in before['events'])
            evidence(case,after=before,disposition=expected.decode().strip())
            if case=='foreign-session':
                command(f,'recover',['Expired','Ready'])


def injected_io(edge, calls, file_hint):
    with request_store() as f:
        command(f,'provision',['Ready'])
        with process(f,'11.'+edge) as p, tempfile.TemporaryDirectory() as tmp:
            rid=read_id(p)
            send_candidate(p,rid)
            wait_stopped(p)
            logfile=Path(tmp)/'io.log'
            trace=['strace','-qq','-yy','-o',str(logfile),'-e','trace='+','.join(calls)]
            for call in calls:
                trace+=['-e',f'inject={call}:error=EIO:when=1']
            with subprocess.Popen([*trace,'-p',str(p.pid)],stderr=subprocess.PIPE) as tracer:
                until=time.monotonic()+10
                while f'TracerPid:\t{tracer.pid}' not in Path(f'/proc/{p.pid}/status').read_text():
                    assert tracer.poll() is None and time.monotonic()<until
                    time.sleep(.01)
                p.send_signal(signal.SIGCONT)
                output,err=p.communicate(timeout=25)
                assert (p.returncode,output)==(1,b'Reconciliation\n'), (output,err)
                tracer.wait(timeout=10)
            failures=[line for line in logfile.read_text().splitlines() if 'EIO' in line and 'INJECTED' in line]
            assert any(file_hint in line for line in failures),failures
        before=snapshot(f)
        command(f,'recover',['Reconciliation'],1)
        assert before==snapshot(f)
        assert len(before['consumed'])==sum(bytes.fromhex(w)[6]==11 for (w,) in before['events'])
        assert before['tip'] in (3,6) and 'user.warband.commit.v1' not in before['dirs'][0]['attrs']
        evidence('io-'+calls[0],failures=failures,after=before,recovery='Reconciliation')


def deadline_and_capacity():
    with request_store() as f:
        command(f,'provision',['Ready'])
        with hold_reader(f):
            with issued(f) as (p,rid):
                assert select.select([p.stdout], [], [], 40)[0]
                assert p.stdout.readline()==b'Expired\n' and p.wait(timeout=10)==0
            assert f.query("SELECT wire FROM request_facts WHERE kind=x'13'")[0][0][104]==1
            assert not list((f.root/'attempts').iterdir())
            for i in range(31):
                with issued(f) as (p,rid):
                    output,err=p.communicate(b'c',timeout=15)
                    assert (p.returncode,output)==(0,b'Expired\n'),err
            before=snapshot(f)
            command(f,'issue-abc',['Limit'],1)
            assert before==snapshot(f) and len(before['events'])==64 and before['tip']==129
            timing=subprocess.run(['/usr/bin/time','-f','%e %M','./model-request','recover'], **actor(f),
                                  capture_output=True,timeout=65)
            assert (timing.returncode,timing.stdout)==(0,b'Ready\n')
            seconds,rss_kib=timing.stderr.decode().strip().split()
            storage={p.name:dict(bytes=p.stat().st_size,allocated=p.stat().st_blocks*512) for directory in ('data','journal')
                     for p in (f.root/directory).iterdir() if p.is_file()}
            evidence('bounded-issuance',confirmed_events=64,tip=129,disposition='Limit',new_admissions=0,
                     retained_files=storage,recovery_seconds=seconds,recovery_maxrss_kib=rss_kib)



def legacy_refusal():
    with request_store() as f:
        command(f,'provision',['Ready'])
        with issued(f) as (p,rid):
            finish_admission(p,rid)
        before=snapshot(f)
        for binary,args in [('marker-intake',[]),('marker-approval',['finalize'])]:
            executable=shutil.copy2(OUT/'reconcile'/binary,f.root/binary)
            result=subprocess.run([executable,*args],input=b'',capture_output=True,**actor(f),timeout=20)
            assert result.returncode!=0 and before==snapshot(f)
            evidence('old-reader-'+binary,disposition=result.stdout.decode().strip(),new_admissions=0)


def schema_identity_and_limits():
    for case in ('schema','ownership','visit-limit'):
        with request_store() as f:
            command(f,'provision',['Ready'])
            if case=='schema':
                f.query('DROP TABLE consumed_requests')
            elif case=='ownership':
                (f.root/'attempts').chmod(0o755)
            else:
                # Count admission rejects the retained row set before reading untrusted bodies.
                f.query("""WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<100001)
                           INSERT INTO events SELECT ?,?,CAST(printf('%08x',i) AS BLOB),x'00' FROM n""",(STORE,LE(1)))
            tip=f.verify()
            command(f,'issue-abc',['Reconciliation'],1)
            assert tip==f.verify() and not list((f.root/'attempts').iterdir())
            evidence(case,tip=tip[4],disposition='Reconciliation',new_admissions=0)


def unavailable_catalog():
    # Enroll a real custody-confirmed issue with an unavailable historical revision.
    with request_store() as donor:
        command(donor,'provision',['Ready'])
        with issued(donor) as (_,rid):
            template=donor.query('SELECT wire FROM request_facts')[0][0]
    with request_store() as f:
        command(f,'provision',['Ready'])
        cp=f.verify()[2]
        body=bytearray(template[:-32])
        body[104:108]=(37).to_bytes(4,'little')
        wire=bytes(body)+cp[32:]
        digest=hashlib.sha256(b'warband.event.v1\0'+body).digest()
        head=hashlib.sha256(b'warband.link.v1\0'+wire[8:40]+cp[32:]+digest).digest()
        pledge=cp+LE(1)+head+digest
        assert f.call(1,pledge)[0]==0
        with contextlib.closing(sqlite3.connect(f.db)) as db, db:
            db.execute('INSERT INTO events VALUES(?,?,?,?)',(STORE,LE(1),LE(1),wire))
            db.execute('INSERT INTO request_facts VALUES(?,?,?,?,?,?)',(STORE,LE(1),LE(1),rid,b'\x12',wire))
        assert f.call(2,pledge)[0]==0
        before=snapshot(f)
        command(f,'recover',['Reconciliation'],1)
        assert before==snapshot(f) and not before['dirs']
        evidence('unknown-catalog-revision',after=before,recovery='Reconciliation')


def run():
    for kind in (18,19):
        for edge in ('before-prepare','prepared','event-inserted','commit-entry','committed','confirmed'):
            crash_case(kind,edge)
    crash_case(1,'confirmed')
    for edge in ('directory','xattr-set','provenance-synced','before-prepare','prepared','event-inserted',
                 'commit-entry','committed','time-synced','confirmed'):
        crash_case(11,edge)
    for edge in ('fail-event-insert','fail-pair-insert','veto-commit'):
        sql_failure(edge)
    duplicate_race()
    retarget_and_rewrite()
    early_denials()
    legacy_refusal()
    schema_identity_and_limits()
    unavailable_catalog()
    injected_io('directory',['fsetxattr'],'/attempts/')
    injected_io('xattr-set',['fsync'],'/attempts/')
    injected_io('commit-entry',['pwrite64'],'active.db-wal')
    injected_io('commit-entry',['fsync','fdatasync'],'active.db-wal')
    late_commit()
    deadline_and_capacity()


if __name__=='__main__':
    run()
