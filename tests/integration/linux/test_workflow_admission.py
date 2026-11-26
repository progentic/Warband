"""Qualify custody-issued selections against the confined synthetic provider on x64-review."""
import contextlib
import json
import os
from pathlib import Path
import select
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time

import test_provider_transport as transport
from test_marker_approval import binding
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


def check_admission(f, genesis, rid, payload, example, deadline):
    issuance, _, wire = replay(f, genesis, [18, 1, 11])
    ref, fingerprint, length, digest = binding(wire)
    assert wire[187:-32] == payload and length == struct.pack('<I', len(payload))
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


def run_case(root, driver, tls, dns, case, example=2):
    payload = {1: b'', 2: b'abc'}[example]
    mode = 'workflow-empty' if example == 1 else 'workflow-abc'
    with request_store() as f:
        command(f, 'provision', ['Ready'])
        genesis = f.verify()[2][32:]
        # The production CLI must reject the proof-only selection input before issuance.
        command(f, mode, [], 2)
        replay(f, genesis, [])
        shutil.copy2(OUT/'reconcile/model-request-proof', f.root/'model-request-proof')
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
            fact, = replay(f, genesis, [18])
            assert f.query('SELECT wire FROM request_facts') == [(fact,)]
            assert fact[56:72] == rid and fact[104:112] == struct.pack('<II', issued.revision, example)
            assert fact[112:144] == sha(payload)
            assert int.from_bytes(fact[152:160], 'little') == issued.deadline_ms
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
            if case in ('control', 'duplicate'):
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
                    assert expiry[56:88] == fact[8:40] and expiry[88:104] == rid
                    assert expiry[104] == 1  # Deadline
                else:
                    assert disposition == 'CandidateRejected' and snapshot(f) == before
                    replay(f, genesis, [18])
                assert not list((f.root/'attempts').iterdir())
                assert not f.query('SELECT request_id FROM consumed_requests')
                report.update(confirmed=0, projection=[0, 0])
            print(json.dumps(report, sort_keys=True), flush=True)


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


if __name__ == '__main__':
    main(Path(sys.argv[1]).resolve(strict=True))
