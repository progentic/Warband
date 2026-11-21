"""Verify live dispatch, confirmed observation and independent evaluation across real restarts."""
import contextlib
import json
import os
import shutil
import signal
import sqlite3
import struct
import subprocess
import time

from test_custody_denial import STORE, VECTORS, emit, limits, sha
from test_receipt_import import OUT, LE, fixture


def boottime_ms():
    return time.clock_gettime_ns(time.CLOCK_BOOTTIME) // 1_000_000


def linked_head(event):
    digest = sha(b'warband.event.v1\0' + event[:-32])
    return sha(b'warband.link.v1\0' + event[8:40] + event[-32:] + digest)


def seed(f):
    vectors = json.loads(VECTORS.read_text())
    proposal = next(p for p in vectors['proposal_recorded'] if p['approval_required'] == 0)
    for seq, vector in enumerate((vectors['task_created'], proposal), 1):
        event = bytes.fromhex(vector['event_hex'])
        pledge = (STORE + LE(1) + LE(seq-1) + event[-32:] + LE(seq) + linked_head(event)
                  + sha(b'warband.event.v1\0' + event[:-32]))
        assert f.call(1, pledge)[0] == 0
        f.query('INSERT INTO events VALUES(?,?,?,?)', (STORE, LE(1), LE(seq), event))
        assert f.call(2, pledge)[0] == 0
    return bytes.fromhex(proposal['proposal_fingerprint'])


def confirmed_events(f, genesis):
    rows = f.query('SELECT sequence,canonical_event FROM events')
    events = [ev for _,ev in sorted(rows, key=lambda row: int.from_bytes(row[0], 'little'))]
    head = genesis
    for seq, ev in enumerate(events, 1):
        assert ev[8:40] == STORE + LE(1) + LE(seq) and ev[-32:] == head
        head = linked_head(ev)
    _, _, checkpoint, pending, _, _ = f.verify()
    assert not pending and checkpoint == STORE + LE(1) + LE(len(events)) + head
    return events


def wait_for_stop(child):
    until = time.monotonic() + 60
    while time.monotonic() < until:
        state = os.waitid(os.P_PID, child.pid, os.WSTOPPED | os.WNOHANG)
        if state is not None:
            assert (state.si_pid, state.si_code, state.si_status) == (child.pid, os.CLD_STOPPED, signal.SIGSTOP), state
            return
        assert child.poll() is None, "issuer exited before proof boundary"
        time.sleep(0.01)
    raise AssertionError('issuer did not stop at proof boundary')


def ticks(output, label):
    return int(next(line.split()[1] for line in output.splitlines() if line.startswith(label+' ')))


def check_evidence(events, original, returned):
    obs, evaluation = events[-2:]
    auth, claim = original[-2:]
    assert auth[88:96] == LE(0) and claim[120:136] == LE(1) + LE(1)
    assert obs[6:8] == LE(5)[:2] and obs[48:52] == struct.pack('<HH',3,1)
    assert obs[56:88] == claim[8:40] and obs[105:107] == b'\x01\0'
    assert obs[104] == (1 if returned else 2)
    assert obs[107:111] == (b'NOOP' if returned else bytes(4))
    assert evaluation[6:8] == LE(6)[:2] and evaluation[48:52] == struct.pack('<HH',4,1)
    assert evaluation[56:88] == obs[8:40] and evaluation[88:120] == claim[8:40]
    assert evaluation[120:152] == sha(b'warband.event.v1\0' + obs[:-32])
    assert evaluation[152:154] == b'\x01\0' and evaluation[154] == (1 if returned else 2)
    ids = {original[0][136:152], original[-2][122:138], obs[88:104], evaluation[155:171]}
    assert len(ids) == 4 and bytes(16) not in ids


def probe_uniqueness(f, event, attempt):
    # A different, valid event Ref prevents the events PK or the FK explaining the refusal.
    original_id = event[120:136]
    other = bytes(b ^ 0xff for b in original_id)
    seq = LE(int.from_bytes(event[32:40],'little')+1)
    for same_attempt in (True, False):
        candidate = bytearray(event)
        candidate[32:40] = seq
        candidate[120:136] = other if same_attempt else original_id
        candidate[-32:] = linked_head(event)
        with contextlib.closing(sqlite3.connect(f.db)) as conn:
            conn.execute('PRAGMA foreign_keys=ON')
            conn.execute('BEGIN')
            conn.execute('INSERT INTO events VALUES(?,?,?,?)',(STORE,LE(1),seq,candidate))
            try:
                conn.execute('INSERT INTO accepted_attempts VALUES(?,?,?,?,?)',
                             (STORE,LE(1),attempt if same_attempt else bytes(b ^ 0xff for b in attempt),
                              candidate[120:136],seq))
            except sqlite3.IntegrityError as exc:
                key = 'attempt_id' if same_attempt else 'transition_id'
                assert 'UNIQUE constraint failed' in str(exc) and str(exc).endswith(key),exc
                emit(constraint=key, outcome='duplicate rejected')
            else:
                raise AssertionError('duplicate accepted')
            finally:
                conn.rollback()


def acceptance_case(f, genesis, kill_at):
    events = confirmed_events(f,genesis)
    original, custody = f.rows(),f.verify()
    ev = events[-1]
    seq = int.from_bytes(ev[32:40],'little')
    assert ev[6:8]==LE(6)[:2]
    normal = shutil.copy2(OUT/'reconcile/accept-noop', f.root/'accept')
    proof = shutil.copy2(OUT/'reconcile/accept-noop-proof', f.root/'accept-proof')
    common = [f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1']
    options = dict(user=f.runtime,group=f.runtime,extra_groups=[],capture_output=True,text=True,timeout=65)

    def run(arguments,expected):
        p = subprocess.run([normal,*common,*arguments],**options)
        result = p.stdout.split()
        assert result and result[0]==expected,(result,p.stderr)
        assert p.returncode==(0 if expected in ('Recorded','Accepted','IndexVerified') else 1)
        return result

    args = [str(seq),'1','2']
    run(args,'IndexOrHistoryInvalid')
    run(['provision-index'],'IndexVerified')
    if kill_at == 'return':
        run(args,'RejectedEvaluation')
    elif kill_at == 'observation':
        # Registered revocation after a verified verdict, at the post-claim control revision.
        auth = events[3]
        previous = linked_head(ev)
        body = (b'WBEV'+struct.pack('<HH',1,9)+STORE+LE(1)+LE(seq+1)+struct.pack('<QHHI',1,2,1,58)
                +auth[8:40]+auth[97:113]+LE(2)+struct.pack('<H',12))
        revoked = body+previous
        pledge = STORE+LE(1)+LE(seq)+previous+LE(seq+1)+linked_head(revoked)+sha(b'warband.event.v1\0'+body)
        assert f.call(1,pledge)[0]==0
        f.query('INSERT INTO events VALUES(?,?,?,?)',(STORE,LE(1),LE(seq+1),revoked))
        assert f.call(2,pledge)[0]==0
        original,custody = f.rows(),f.verify()
        run(args,'Revoked')
    else:
        run([str(seq),'2','2'],'StaleVersions')
        run([str(seq),'1','1'],'StaleVersions')
        assert f.rows()==original and f.verify()==custody
        with subprocess.Popen([proof,*common,*args],user=f.runtime,group=f.runtime,extra_groups=[],
                              stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) as first:
            try:
                wait_for_stop(first)
                run(args,'LockUnavailable')
                assert f.rows()==original and f.verify()==custody
                first.send_signal(signal.SIGCONT)
                output,err = first.communicate(timeout=65)
                assert first.returncode==0 and output.split()[0]=='Accepted',(output,err)
            finally:
                if first.poll() is None:
                    first.kill()
                    first.wait(timeout=10)
        final = confirmed_events(f,genesis)
        assert final[:-1]==events and f.verify()[4]==custody[4]+2
        transition,claim = final[-1],events[4]
        assert transition[6:8]==LE(7)[:2] and transition[48:52]==struct.pack('<HH',5,1)
        assert transition[56:120]==ev[8:40]+claim[8:40] and transition[136:161]==LE(1)+LE(2)+LE(2)+b'\x02'
        tid = transition[120:136]
        row = (STORE,LE(1),claim[88:104],tid,LE(seq+1))
        assert f.query('SELECT * FROM accepted_attempts')==[row]
        assert output.split()[1:]==[STORE.hex(),'1',str(seq+1),tid.hex(),'2','3']
        original,custody = f.rows(),f.verify()
        assert run(args,'Recorded')[1:]==output.split()[1:]
        run([str(seq),'2','3'],'StaleVersions')
        probe_uniqueness(f,transition,claim[88:104])
        f.query('DELETE FROM accepted_attempts')
        run(args,'IndexOrHistoryInvalid')
        run(['provision-index'],'IndexRefused')
        f.query('DROP TABLE accepted_attempts')
        # A SQLite-only suffix cannot be used even to provision a derived table.
        extra = bytearray(transition)
        extra[32:40] = LE(seq+2)
        extra[-32:] = linked_head(transition)
        f.query('INSERT INTO events VALUES(?,?,?,?)',(STORE,LE(1),LE(seq+2),extra))
        run(['provision-index'],'IndexRefused')
        assert not f.query("SELECT name FROM sqlite_schema WHERE name='accepted_attempts'")
        f.query('DELETE FROM events WHERE sequence=?',(LE(seq+2),))
        run(['provision-index'],'IndexVerified')
        assert f.query('SELECT * FROM accepted_attempts')==[row]
        assert run(args,'Recorded')[1:]==output.split()[1:]
        emit(acceptance=output.strip(),loser='LockUnavailable',retry='Recorded',tip=custody[4])
    assert f.rows()==original and f.verify()==custody
    if kill_at is not None:
        assert not f.query('SELECT * FROM accepted_attempts')
        emit(refused='RejectedEvaluation' if kill_at=='return' else 'Revoked',tip=custody[4],pending=False)


def exercise(kill_at):
    with fixture() as (f, genesis, _):
        fingerprint = seed(f)
        gate = shutil.copy2(OUT/'reconcile/noop-gate-proof', f.root/'noop-gate')
        args = [gate, f.db, f.root/'endpoints/runtime.sock', str(f.custodian), STORE.hex(), '1', '2']
        options = dict(user=f.runtime, group=f.runtime, extra_groups=[], stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, text=True)
        with subprocess.Popen(args, **options) as issuer:
            try:
                wait_for_stop(issuer)
                original = confirmed_events(f, genesis)
                assert [int.from_bytes(e[6:8], 'little') for e in original] == [1,2,8,3,4]
                auth, claim = original[-2:]
                assert auth[56:88] == original[1][8:40] and auth[96] == auth[121] == 1
                assert claim[56:88] == auth[8:40] and claim[104:120] == auth[97:113]
                assert claim[136:168] == fingerprint
                stopped_events = original
                if kill_at != 'claim':
                    issuer.send_signal(signal.SIGCONT)
                    wait_for_stop(issuer)  # primitive returned; no observation prepared yet
                    assert confirmed_events(f,genesis) == original
                    if kill_at != 'return':
                        issuer.send_signal(signal.SIGCONT)
                        wait_for_stop(issuer)  # observation confirmed; no evaluation prepared yet
                        stopped_events = confirmed_events(f,genesis)
                        assert stopped_events[:-1] == original and stopped_events[-1][6:8] == b'\x05\0'
                        observation_tip = f.verify()[4]
                if kill_at:
                    before_exit = boottime_ms()
                    issuer.kill()
                else:
                    issuer.send_signal(signal.SIGCONT)
                issued, err = issuer.communicate(timeout=65)
                after_exit = boottime_ms()
            finally:
                if issuer.poll() is None:
                    issuer.kill()
                    issuer.wait(timeout=10)
        fields = next(line.split() for line in issued.splitlines() if line.startswith('authorization_start_ms '))
        start, confirmation = int(fields[1]), int(fields[3])
        assert fields[2] == 'claim_confirmed_ms' and start <= confirmation < start+90_000
        if kill_at:
            assert issuer.returncode == -signal.SIGKILL
            assert issued.splitlines().count('primitive_invoked') == (0 if kill_at == 'claim' else 1)
            if kill_at != 'claim':
                assert 'returned NOOP' in issued
            with subprocess.Popen(args, **options) as fresh:
                try:
                    output, err = fresh.communicate(timeout=65)
                finally:
                    if fresh.poll() is None:
                        fresh.kill()
                        fresh.wait(timeout=10)
            assert output.splitlines().count('primitive_invoked') == 0
            final = confirmed_events(f,genesis)
            if kill_at == 'observation':
                assert fresh.returncode == 0 and 'gate_result EvaluationVerified' in output, (output,err)
                assert final[:-1] == stopped_events and f.verify()[4] == observation_tip + 2
                check_evidence(final,original,True)
            else:
                assert fresh.returncode == 1 and 'gate_result NoLiveGrantEntry' in output, (output, err)
                tick = ticks(output,'dispatch_ms')
                assert confirmation <= before_exit <= after_exit <= tick < start+90_000
                assert final[:-3] == original
                denial = final[-3]
                assert denial[6:8] == b'\x08\0' and denial[48:50] == b'\x02\0'
                assert denial[56:60] == b'\x03\x09\0\x01' and denial[60:92] == claim[8:40]
                assert denial[92:124] == sha(claim)
                assert 'confirmed_evidence 4 5' in output
                check_evidence(final,original,False)
                emit(case='fresh', issuer=issuer.pid, fresh=fresh.pid, start=start, confirmed=confirmation,
                     exit_before=before_exit, exit_after=after_exit, dispatch_check=tick, invocations=0, reason=9)
            rows, custody = f.rows(), f.verify()
            again = subprocess.run(args,timeout=65,**options)
            expected = 'EvaluationVerified' if kill_at == 'observation' else 'EvaluationRejected'
            assert again.returncode == (0 if kill_at == 'observation' else 1)
            assert 'gate_result '+expected in again.stdout and 'primitive_invoked' not in again.stdout
            assert f.rows() == rows and f.verify() == custody
            emit(case=kill_at,retry=expected,events=len(final),tip=custody[4],
                 observation_digest=final[-1][120:152].hex(), verdict=final[-1][154])
        else:
            output = issued
            assert issuer.returncode == 0 and 'gate_result Dispatched' in output, (output,err)
            assert output.splitlines().count('primitive_invoked') == 1 and 'returned NOOP' in output
            tick = ticks(output,'dispatch_ms')
            assert confirmation <= tick < start+90_000
            final = confirmed_events(f,genesis)
            assert final[:-2] == original and 'confirmed_evidence 4 5' in output
            check_evidence(final,original,True)
            emit(case='issuer', issuer=issuer.pid, start=start, confirmed=confirmation, dispatch_check=tick, invocations=1)

        if kill_at != 'claim':
            acceptance_case(f,genesis,kill_at)


if __name__ == '__main__':
    assert os.getuid() == 0 and limits('self') == (256*1024*1024,0)
    for boundary in (None,'claim','return','observation'):
        exercise(boundary)
    emit(result='pass')
