"""Qualify custody-issued selections against the confined synthetic provider on x64-review."""
import contextlib
import fcntl
import json
import os
import re
from pathlib import Path
import select
import signal
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time

import test_provider_transport as transport
from test_marker_approval import binding, cli, server, wire_peer
from test_custody_denial import as_user
from test_model_request import actor, command, request_store
from test_provider_connector import DNS, STUB
from test_receipt_import import LE, OUT, STORE, sha
from test_request_recovery import snapshot


def line(process):
    if not select.select([process.stdout], [], [], 15)[0]:
        raise TimeoutError('model-request did not report a disposition')
    return process.stdout.readline().decode().strip()


def replay(f, genesis, kinds):
    rows = f.query('SELECT canonical_event FROM events ORDER BY sequence')
    events = [wire for wire, in rows]
    assert [wire[6] for wire in events] == kinds
    head = genesis
    for sequence, wire in enumerate(events, 1):
        ref = STORE + LE(1) + LE(sequence)
        assert wire[8:40] == ref and wire[-32:] == head
        head = sha(b'warband.link.v1\0' + ref + head + sha(b'warband.event.v1\0' + wire[:-32]))
    _, _, checkpoint, pending, _, _ = f.verify()
    assert checkpoint == STORE + LE(1) + LE(len(events)) + head and not pending
    return events


def check_admission(f, genesis, rid, payload, example, deadline, prior=()):
    issuance, _, wire = replay(f, genesis, [*prior, 18, 1, 11])[-3:]
    ref, fingerprint, length, digest = binding(wire)
    assert wire[187:-32] == payload and length == struct.pack('<I', len(payload))
    assert fingerprint == sha(b'warband.marker.proposal.v1\0'+ref+wire[56:187]+payload)
    assert struct.unpack_from('<QQ', wire, 152) == (1, 0)
    assert f.query('SELECT request_id,store_id,epoch,sequence,catalog_id,payload_digest,event_digest,'
                   'fingerprint FROM consumed_requests') == [
        (rid, ref[:16], ref[16:24], ref[24:], struct.pack('<I', example), digest,
         sha(b'warband.event.v1\0' + wire[:-32]), fingerprint)]
    directory, = (f.root / 'attempts').iterdir()
    assert not list(directory.iterdir()) and os.getxattr(directory, 'user.warband.request.v1') == rid
    proof = os.getxattr(directory, 'user.warband.commit.v1')
    assert len(proof) == 56 and proof[:48] == rid + sha(b'warband.event.v1\0' + wire[:-32])
    assert int.from_bytes(issuance[144:152], 'little') <= int.from_bytes(proof[48:], 'little') < deadline
    return ref.hex(), fingerprint.hex()


REVIEW_CASES = ('approve', 'reject', 'disconnect', 'ref', 'fingerprint', 'length', 'digest',
                'directory', 'issuer-lost', 'provenance', 'commit12', 'commit13')


def review_case(f, process, case, genesis, rid, payload, issued):
    ref, fp = check_admission(f, genesis, rid, payload, issued.example, issued.deadline_ms)
    assert line(process) == 'AwaitingOperator'
    wire = replay(f, genesis, [18, 1, 11])[-1]
    directory, = (f.root/'attempts').iterdir()
    inode = directory.stat()
    held = [fd for fd in Path(f'/proc/{process.pid}/fd').iterdir() if os.path.samestat(fd.stat(), inode)]
    assert len(held) == 1
    initial = snapshot(f)

    def after_display():
        assert os.path.samestat(held[0].stat(), inode)
        with f.db.open('rb') as gate:
            fcntl.flock(gate, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if case == 'directory':
            directory.rename(f.root/'original-attempt')
            directory.mkdir(mode=0o700)
            os.chown(directory, f.runtime, f.runtime)
            assert os.path.samestat(held[0].stat(), inode) and not os.path.samestat(directory.stat(), inode)
        elif case == 'provenance':
            os.removexattr(directory, 'user.warband.commit.v1')

    expected = {'approve':'Permitted', 'reject':'Rejected', 'disconnect':'Withheld',
                'directory':'ReconciliationRequired', 'provenance':'ReconciliationRequired'}
    interrupted = case in ('commit12', 'commit13')
    if case == 'issuer-lost':
        process.kill()
        assert process.wait(timeout=5) == -signal.SIGKILL
        wrong_id = bytes([rid[0] ^ 1]) + rid[1:]
        lookup = subprocess.run(['./review', 'receipts', wrong_id.hex()], **actor(f),
                                capture_output=True, timeout=10)
        assert lookup.returncode == 1 and not lookup.stdout
        with server(f, 'receipts', 0, rid) as receipt:
            assert cli(f, wire, b'approve', payload=payload) == (1, 'DirectoryHold')
            assert line(receipt) == 'DirectoryHold LiveGrant false'
        outcome = 'DirectoryHold'
    elif interrupted:
        as_user(f.operator, lambda: wire_peer(f, 'lost_reply', wire))
        until = time.monotonic() + 10
        while time.monotonic() < until:
            stop = os.waitid(os.P_PID, process.pid, os.WSTOPPED | os.WEXITED | os.WNOHANG | os.WNOWAIT)
            if stop:
                assert (stop.si_code, stop.si_status) == (os.CLD_STOPPED, signal.SIGSTOP)
                break
            time.sleep(.01)
        else:
            raise TimeoutError('missing post-COMMIT stop')
        process.kill()
        assert process.wait(timeout=5) == -signal.SIGKILL
        tail = int(case[-2:])
        assert f.verify()[3] and f.rows()[0][-1][3][6] == tail
        # Historical confirmation can finish only for the authenticated matching decision.
        with server(f, 'receipts', 0, rid):
            assert cli(f, wire, b'reject', payload=payload) == (1, 'DecisionConflict')
        with server(f, 'receipts', 0, rid) as receipt:
            assert cli(f, wire, b'approve', payload=payload) == (0, f'Recorded {STORE.hex()} 1 4')
            assert line(receipt) == 'Recorded LiveGrant false'
        outcome = 'Recorded'
    else:
        outcome = expected.get(case, 'BindingMismatch')
        if case in expected:
            answer = None if case == 'disconnect' else b'reject' if case == 'reject' else b'approve'
            rc, reply = cli(f, wire, answer, after_display, payload)
            suffix = f' {STORE.hex()} 1 4' if case in ('approve', 'reject') else ''
            assert (rc, reply) == (int(not suffix), '' if case == 'disconnect' else outcome+suffix)
        else:
            as_user(f.operator, lambda: wire_peer(f, case, wire))
        assert line(process) == outcome
        assert process.wait(timeout=5) == int(case not in ('approve', 'reject'))

    decided = case in ('approve', 'reject') or interrupted
    permitted = case in ('approve', 'commit13')
    events = replay(f, genesis, [18, 1, 11] + [12]*decided + [13]*permitted)
    assert events[2] == wire
    if decided:
        decision = events[3]
        assert decision[56:165] == b''.join(binding(wire)) + LE(f.operator) + bytes([2 if case=='reject' else 1])
        if permitted:
            assert events[4][56:88] == decision[8:40] and events[4][120] == 1
        settled = snapshot(f)
        # A fresh service has no original descriptor. Repeating the decision only reads its receipt.
        with server(f, 'receipts', int(permitted), rid) as receipt:
            answer = b'reject' if case=='reject' else b'approve'
            assert cli(f, wire, answer, payload=payload) == (0, f'Recorded {STORE.hex()} 1 4')
            assert line(receipt) == 'Recorded LiveGrant false'
        assert settled == snapshot(f)
    final = snapshot(f)
    assert final['consumed'] == initial['consumed'] and final['requests'] == initial['requests']
    if not decided:
        assert final['checkpoint'] == initial['checkpoint'] and final['tip'] == initial['tip']
    assert not list(directory.iterdir())
    return dict(outcome=outcome, ref=ref, fingerprint=fp, decisions=int(decided), permits=int(permitted),
                projection=[1, int(permitted)], issuer_pid=process.pid)


@contextlib.contextmanager
def issuing(f, genesis, case, example, mode, review=False, prior=()):
    binary = 'model-request-proof'
    if review:
        shutil.copy2(OUT/'reconcile/marker-approval', f.root/'review')
        if case.startswith('commit'):
            binary += '-' + case
    shutil.copy2(OUT/'reconcile'/binary, f.root/'model-request-proof')
    parent, child = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    with parent, child, contextlib.ExitStack() as cleanup:
        process = subprocess.Popen(['./model-request-proof', mode], **actor(f), stdin=child,
                                   stdout=subprocess.PIPE, bufsize=0)
        cleanup.callback(process.stdout.close)
        cleanup.callback(process.wait, timeout=5)
        cleanup.callback(process.kill)
        child.close()
        status, text, revision, selected, deadline = line(process).split()
        rid = bytes.fromhex(text)
        issued = transport.Issuance(text.encode(), int(revision), int(selected), int(deadline))
        assert status == 'Issued' and issued.example == example and issued.revision == 1
        fact = replay(f, genesis, [*prior, 18])[-1]
        assert f.query('SELECT wire FROM request_facts WHERE request_id=?', (rid,)) == [(fact,)]
        assert fact[56:72] == rid and fact[104:112] == struct.pack('<II', issued.revision, example)
        assert fact[112:144] == sha({1:b'', 2:b'abc'}[example])
        assert int.from_bytes(fact[152:160], 'little') == issued.deadline_ms
        yield process, parent, issued


def run_case(root, driver, tls, dns, case, example=2):
    payload = {1: b'', 2: b'abc'}[example]
    mode = 'workflow-empty' if example == 1 else 'workflow-abc'
    if case in REVIEW_CASES:
        mode = 'workflow-review-empty' if example == 1 else 'workflow-review-abc'
    with request_store() as f:
        command(f, 'provision', ['Ready'])
        genesis = f.verify()[2][32:]
        # The production CLI must reject the proof-only selection input before issuance.
        command(f, mode, [], 2)
        replay(f, genesis, [])
        with issuing(f, genesis, case, example, mode, case in REVIEW_CASES) as (process, parent, issued):
            rid = bytes.fromhex(issued.request_id.decode())
            before = snapshot(f)
            row = transport.exercise(root, [str(driver)], tls, 'success', bootstrap=True, dns=dns, issuance=issued)
            assert row['passed'] and row['requests'] == 1 and row['connections'] == 1, row['disposition']
            selection = row.pop('selection')
            assert selection == issued.request_id + struct.pack('<II', example, len(payload))
            assert process.poll() is None and snapshot(f) == before

            if case == 'wrong-id':
                selection = (b'1' if selection[:1] == b'0' else b'0') + selection[1:]
            elif case == 'wrong-example':
                selection = selection[:32] + struct.pack('<I', 1) + selection[36:]
            elif case == 'wrong-length':
                selection = selection[:36] + struct.pack('<I', len(payload)+1)
            elif case == 'expired':
                time.sleep(max(0, issued.deadline_ms - transport.now_ms()) / 1000 + .025)
            parent.sendall(selection)
            disposition = line(process)
            report = dict(case=case, catalog=example, disposition=disposition, requests=row['requests'])
            if case in REVIEW_CASES:
                assert disposition == 'Admitted'
                report.update(review_case(f, process, case, genesis, rid, payload, issued))
            elif case in ('control', 'duplicate'):
                assert disposition == 'Admitted'
                ref, fingerprint = check_admission(f, genesis, rid, payload, example, issued.deadline_ms)
                settled = snapshot(f)
                if case == 'duplicate':
                    parent.sendall(selection)
                    assert line(process) == 'Consumed'
                parent.shutdown(socket.SHUT_WR)
                assert process.wait(timeout=5) == int(case == 'duplicate')
                command(f, 'recover', ['Ready'])  # production replay and pair verification
                assert snapshot(f) == settled
                report.update(ref=ref, fingerprint=fingerprint, projection=[1, 0], confirmed=1)
                if case == 'duplicate':
                    report.update(redelivery='Consumed', duplicate_new_admissions=0)
            else:
                assert process.wait(timeout=5) == 1
                if case == 'expired':
                    assert disposition == 'Expired'
                    _, expiry = replay(f, genesis, [18, 19])
                    assert expiry[56:88] == STORE+LE(1)+LE(1) and expiry[88:104] == rid
                    assert expiry[104] == 1  # Deadline
                else:
                    assert disposition == 'CandidateRejected' and snapshot(f) == before
                    replay(f, genesis, [18])
                assert not list((f.root/'attempts').iterdir())
                assert not f.query('SELECT request_id FROM consumed_requests')
                report.update(confirmed=0, projection=[0, 0])
            print(json.dumps(report, sort_keys=True), flush=True)


def provider_round(f, genesis, root, driver, tls, dns, case, *, prior=(), previous='', review=False, example=2):
    mode = 'workflow-review-abc' if review else 'workflow-empty' if example==1 else 'workflow-abc'
    with issuing(f, genesis, case, example, mode, review, prior) as (process, parent, issued):
        before = snapshot(f)
        row = transport.exercise(root, [str(driver)], tls, case, bootstrap=True, dns=dns,
                                 previous=previous, issuance=issued)
        assert row['passed'] and row['requests']==row['connections']==1 and row['exact_request_bytes']
        selection = row.pop('selection')
        assert snapshot(f)==before and process.poll() is None
        rid = bytes.fromhex(issued.request_id.decode())
        result = dict(fixture=case, disposition=row['disposition'], request_id=rid.hex(), issuer=process.pid,
                      catalog=example, reply_sha256=row['reply_sha256'], sent_sha256=row['observed_sha256'], exact_body=row['exact_request_bytes'],
                      requests=row['requests'], selection=selection is not None)
        if previous:
            result['prior_sha256'] = sha(previous.encode()).hex()
        if selection is None or case=='success':  # Hold the first valid reply for the stale-delivery fixture.
            assert (selection is None) == (row['disposition']!='Ok')
            parent.shutdown(socket.SHUT_WR)
            assert process.wait(timeout=5)==1 and process.stdout.read()==b'' and snapshot(f)==before
            assert not before['consumed'] and not before['dirs']
            command(f, 'recover', ['Expired', 'Ready'])
            facts = replay(f, genesis, [*prior,18,19])
            assert facts[-1][88:104]==rid and facts[-1][104]==3  # SessionLost
            assert not f.query('SELECT request_id FROM consumed_requests') and not list((f.root/'attempts').iterdir())
            result.update(kinds=[w[6] for w in facts], consumptions=0)
        else:
            parent.sendall(selection)
            assert line(process)=='Admitted'
            ref, fp = check_admission(f, genesis, rid, b'abc', 2, issued.deadline_ms, prior)
            kinds = [*prior,18,1,11]
            wire = replay(f, genesis, kinds)[-1]
            result.update(ref=ref, fingerprint=fp, consumptions=1)
            if review:
                assert line(process)=='AwaitingOperator'
                if case=='audit-tamper':
                    # Keep valid framing and change one payload byte, leaving custody untouched.
                    altered = bytearray(wire)
                    altered[187] ^= 1
                    cp = f.verify()[2]
                    f.query('UPDATE events SET canonical_event=? WHERE sequence=?',(bytes(altered),wire[32:40]))
                    changed = snapshot(f)
                    assert not changed['pledge'] and changed['checkpoint']==cp.hex()
                    assert sha(b'warband.link.v1\0'+wire[8:40]+wire[-32:]+sha(b'warband.event.v1\0'+altered[:-32]))!=cp[32:]
                    client = subprocess.run(['./review','decide'],input=b'approve\n',**actor(f,f.operator),
                                            capture_output=True,timeout=10)
                    assert (client.returncode,client.stdout,client.stderr)==(1,b'',b'')
                    assert line(process)=='ReconciliationRequired' and process.wait(timeout=5)==1
                    assert snapshot(f)==changed and bytes.fromhex(changed['events'][-1][0])==bytes(altered)
                    result.update(chain='mismatch', review='ReconciliationRequired', display=False)
                else:
                    # The earlier rejected instruction must confer no approval on this fresh request.
                    start = snapshot(f)
                    with subprocess.Popen(['./review','decide'],**actor(f,f.operator),stdin=subprocess.PIPE,
                                          stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0) as client:
                        display = [line(client) for _ in range(6)]
                        assert display[0]==f'Proposal {STORE.hex()} 1 {len(kinds)}'
                        assert display[4]==f'Fingerprint {fp} Length 3 SHA256 {sha(b"abc").hex()}'
                        assert display[5]=='Type approve or reject and press Enter.' and snapshot(f)==start
                        out, err = client.communicate(b'approve\n',timeout=10)
                        assert client.returncode==0 and not err and out.decode().strip()==f'Permitted {STORE.hex()} 1 {len(kinds)+1}'
                    assert line(process)=='Permitted' and process.wait(timeout=5)==0
                    kinds += [12,13]
                    decision, permit = replay(f, genesis, kinds)[-2:]
                    assert decision[56:165]==b''.join(binding(wire))+LE(f.operator)+b'\1'
                    assert permit[56:88]==decision[8:40]
                    result.update(review='Permitted')
            else:
                parent.shutdown(socket.SHUT_WR)
                assert process.wait(timeout=5)==0
            result['kinds']=kinds
        # Scan original durable bytes, including the enrolled custodian's history.
        for table in ('events','request_facts','consumed_requests'):
            for record in f.query('SELECT * FROM '+table):
                for field in record:
                    if isinstance(field,bytes): clean_output(field)
        for item in (f.root/'data').iterdir():
            if item.is_file(): clean_output(item.read_bytes())
        print(json.dumps(result,sort_keys=True),flush=True)
        return issued


def clean_output(data):
    assert all(prefix not in data for prefix in (b'WBEXIT_', b'WB3D_SECRET_', b'WB3D_BODY_', b'WB3D_EXCLUDED_')), 'fixture canary escaped'


def exit_fixtures(root, driver, tls, dns):
    for case in ('bad-content','unknown-action','target-path','schema-two','substitute-bytes','assert-success',
                 'success-only','tool-secret','tool-result','error-secret','audit-tamper','replay-reply','promote-action'):
        with request_store() as f:
            command(f,'provision',['Ready'])
            genesis=f.verify()[2][32:]
            args=(f, genesis, root, driver, tls, dns)
            if case in ('replay-reply','promote-action'):
                promotion = case=='promote-action'
                first = provider_round(*args, case if promotion else 'success', example=1 if promotion else 2)
                prior_reply = dns.prior_reply
                assert first.request_id.decode() in prior_reply
                if promotion: assert 'WBEXIT_PROMOTE_' in prior_reply
                second = provider_round(*args, 'promotion-followup' if promotion else case, prior=(18,19),
                                        previous=prior_reply, review=promotion)
                assert first.request_id!=second.request_id
            else:
                provider_round(*args, case, review=case=='audit-tamper')


def main(driver):
    if not __debug__ or os.geteuid() or os.uname().release != '6.8.0-142-generic':
        raise RuntimeError('requires assertions and the preproduction qualification kernel')
    if os.stat('/proc/self/ns/net').st_ino == os.stat('/proc/1/ns/net').st_ino or socket.if_nameindex() != [(1, 'lo')]:
        raise RuntimeError('requires a fresh, unrouted namespace')
    for path in (driver, *driver.parents):
        st = path.stat()
        if st.st_uid or st.st_mode & 0o022:
            raise RuntimeError('unprotected fixture driver')
    subprocess.run(['ip', 'link', 'set', 'lo', 'up'], check=True)
    subprocess.run(['ip', 'addr', 'add', transport.TARGET[0]+'/32', 'dev', 'lo'], check=True)
    with tempfile.TemporaryDirectory() as tmp, transport.observing(transport.Observer(STUB, DNS)) as dns:
        dns.hold = False
        root = Path(tmp)
        tls, _, _ = transport.fixture_tls(root)
        # /run is a noexec staging mount on x64-review. Use the protected fixture directory.
        executable = root/'driver'
        shutil.copyfile(driver, executable)
        executable.chmod(0o555)
        assert sha(executable.read_bytes()) == sha(driver.read_bytes())
        for case in ('control', 'wrong-id', 'wrong-example', 'wrong-length', 'expired', 'duplicate'):
            run_case(root, executable, tls, dns, case)
        run_case(root, executable, tls, dns, 'control', example=1)
        for case in REVIEW_CASES:
            run_case(root, executable, tls, dns, case)
        run_case(root, executable, tls, dns, 'approve', example=1)
        exit_fixtures(root, executable, tls, dns)


def grade_launches(evidence):
    records = [json.loads(line) for line in (evidence/'cases.jsonl').read_text().splitlines() if line.startswith('{')]
    reviews = [row for row in records if 'issuer_pid' in row]
    expected = [(case, 2) for case in REVIEW_CASES] + [('approve', 1)]
    assert sorted((row['case'], row['catalog']) for row in reviews) == sorted(expected)
    traces = evidence/'traces'
    for row in reviews:
        calls = (traces/f"trace.{row['issuer_pid']}").read_text().splitlines()
        execs = [s for s in calls if s.startswith(('execve(', 'execveat('))]
        mode = 'workflow-review-empty' if row['catalog'] == 1 else 'workflow-review-abc'
        assert len(execs) == 1 and f'"./model-request-proof", "{mode}"' in execs[0]
        assert execs[0].rstrip().endswith('= 0')
        assert not any(s.startswith(('clone(', 'clone3(', 'fork(', 'vfork(')) for s in calls)
    for row in (r for r in records if 'fixture' in r):
        calls = (traces/f"trace.{row['issuer']}").read_text().splitlines()
        execs = [s for s in calls if s.startswith(('execve(', 'execveat('))]
        assert len(execs)==1 and '"./model-request-proof", "workflow-' in execs[0] and execs[0].endswith('= 0')
        assert not any(s.startswith(('clone(', 'clone3(', 'fork(', 'vfork(')) for s in calls)
    for trace in traces.glob('trace.*'):
        for binary in re.findall(r'^execve(?:at)?\((?:[^"]*, )?"([^"]+)"', trace.read_text(), re.M):
            assert Path(binary).name not in ('marker-worker', 'marker-supervisor', 'worker-probe')
    print(json.dumps(dict(graded_reviews=len(reviews), worker_launches=0)), flush=True)


if __name__ == '__main__':
    if sys.argv[1:2] == ['--grade-launches'] and len(sys.argv) == 3:
        if not __debug__:
            raise SystemExit('qualification requires assertions')
        grade_launches(Path(sys.argv[2]))
    else:
        main(Path(sys.argv[1]).resolve(strict=True))
