"""Verify live dispatch, confirmed observation and independent evaluation across real restarts."""
import json
import os
import shutil
import signal
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


if __name__ == '__main__':
    assert os.getuid() == 0 and limits('self') == (256*1024*1024,0)
    for boundary in (None,'claim','return','observation'):
        exercise(boundary)
    emit(result='pass')
