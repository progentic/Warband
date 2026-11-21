"""Paired live-grant proof on real SQLite, custodian and runtime processes."""
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


def stop_at_claim(child):
    until = time.monotonic() + 60
    while time.monotonic() < until:
        state = os.waitid(os.P_PID, child.pid, os.WSTOPPED | os.WEXITED | os.WNOHANG | os.WNOWAIT)
        if state is not None:
            assert (state.si_pid, state.si_code, state.si_status) == (child.pid, os.CLD_STOPPED, signal.SIGSTOP), state
            return
        time.sleep(0.01)
    raise AssertionError('issuer did not stop at confirmed claim')


def ticks(output, label):
    return int(next(line.split()[1] for line in output.splitlines() if line.startswith(label+' ')))


def exercise(restart):
    with fixture() as (f, genesis, _):
        fingerprint = seed(f)
        gate = shutil.copy2(OUT/'reconcile/noop-gate-proof', f.root/'noop-gate')
        args = [gate, f.db, f.root/'endpoints/runtime.sock', str(f.custodian), STORE.hex(), '1', '2']
        options = dict(user=f.runtime, group=f.runtime, extra_groups=[], stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, text=True)
        with subprocess.Popen(args, **options) as issuer:
            try:
                stop_at_claim(issuer)
                original = confirmed_events(f, genesis)
                assert [int.from_bytes(e[6:8], 'little') for e in original] == [1,2,8,3,4]
                auth, claim = original[-2:]
                assert auth[56:88] == original[1][8:40] and auth[96] == auth[121] == 1
                assert claim[56:88] == auth[8:40] and claim[104:120] == auth[97:113]
                assert claim[136:168] == fingerprint
                if restart:
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
        if restart:
            assert issuer.returncode == -signal.SIGKILL and 'primitive_invoked' not in issued
            with subprocess.Popen(args, **options) as fresh:
                try:
                    output, err = fresh.communicate(timeout=65)
                finally:
                    if fresh.poll() is None:
                        fresh.kill()
                        fresh.wait(timeout=10)
            assert fresh.returncode == 1 and 'gate_result NoLiveGrantEntry' in output, (output, err)
            assert output.splitlines().count('primitive_invoked') == 0
            tick = ticks(output,'dispatch_ms')
            assert confirmation <= before_exit <= after_exit <= tick < start+90_000
            final = confirmed_events(f,genesis)
            assert final[:-1] == original
            denial = final[-1]
            assert denial[6:8] == b'\x08\0' and denial[48:50] == b'\x02\0'
            assert denial[56:60] == b'\x03\x09\0\x01' and denial[60:92] == claim[8:40]
            assert denial[92:124] == sha(claim)
            emit(case='fresh', issuer=issuer.pid, fresh=fresh.pid, start=start, confirmed=confirmation,
                 exit_before=before_exit, exit_after=after_exit, dispatch_check=tick, invocations=0, reason=9)
        else:
            output = issued
            assert issuer.returncode == 0 and 'gate_result Dispatched' in output, (output,err)
            assert output.splitlines().count('primitive_invoked') == 1 and 'returned NOOP' in output
            tick = ticks(output,'dispatch_ms')
            assert confirmation <= tick < start+90_000 and confirmed_events(f,genesis) == original
            emit(case='issuer', issuer=issuer.pid, start=start, confirmed=confirmation, dispatch_check=tick, invocations=1)
        assert 'confirmed_evidence 4 5' in output


if __name__ == '__main__':
    assert os.getuid() == 0 and limits('self') == (256*1024*1024,0)
    exercise(False)
    exercise(True)
    emit(result='pass')
