"""Exercise the runtime request writer with a real SQLite store and enrolled custodian."""
import contextlib
import hashlib
import os
import select
import shutil
import struct
import subprocess

from test_receipt_import import ENROLL, LE, OUT, STORE, fixture


@contextlib.contextmanager
def request_store():
    with fixture(fresh=True) as (f, _, _):
        assert f.call(4, ENROLL)[0] == 0
        journal = f.root / 'journal'
        os.chown(journal, f.runtime, f.runtime)
        journal.chmod(0o700)
        f.provision()
        cp = f.verify()[2]
        (f.root / 'intake.anchor').write_bytes(cp + struct.pack('<I', f.custodian))
        (f.root / 'approval.ids').write_bytes(struct.pack('<II', f.runtime, f.operator))
        attempts = f.root / 'attempts'
        attempts.mkdir(mode=0o700)
        os.chown(attempts, f.runtime, f.runtime)
        shutil.copy2(OUT / 'reconcile/model-request', f.root / 'model-request')
        yield f


def actor(f, uid=None):
    uid = f.runtime if uid is None else uid
    return dict(cwd=f.root, user=uid, group=uid, extra_groups=[])


def command(f, mode, expected, rc=0):
    result = subprocess.run(['./model-request', mode], **actor(f), capture_output=True, timeout=65)
    assert (result.returncode, result.stdout.decode().splitlines()) == (rc, expected), (result, expected)


@contextlib.contextmanager
def issued(f):
    proc = subprocess.Popen(['./model-request', 'issue-abc'], **actor(f), stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    try:
        assert select.select([proc.stdout], [], [], 15)[0]
        line = proc.stdout.readline().split()
        assert len(line) == 2 and line[0] == b'Issued', line
        request_id = bytes.fromhex(line[1].decode())
        wire, = f.query('SELECT wire FROM request_facts')[0]
        assert wire[6:8] == b'\x12\x00' and wire[56:72] == request_id
        assert wire[104:112] == struct.pack('<II', 1, 2)
        assert wire[112:144] == hashlib.sha256(b'abc').digest()
        start, deadline = struct.unpack_from('<QQ', wire, 144)
        assert deadline - start == 30000
        assert f.rows()[0][0][3] == wire and f.verify()[2][24:32] == LE(1)
        yield proc, request_id
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait(timeout=5)


def issuance_and_expiry():
    for case in ('cancel', 'restart', 'tamper', 'remove_expiry'):
        with request_store() as f:
            command(f, 'issue-abc', ['Reconciliation'], 1)
            command(f, 'provision', ['Ready'])
            with issued(f) as (proc, request_id):
                command(f, 'recover', ['Unavailable'], 1)
                if case == 'cancel':
                    proc.stdin.write(b'c')
                    output, err = proc.communicate(timeout=10)
                    assert (proc.returncode, output) == (0, b'Expired\n'), err
            if case == 'tamper':
                wire, = f.query('SELECT wire FROM request_facts')[0]
                changed = bytearray(wire)
                changed[108:112] = struct.pack('<I', 1)
                changed[112:144] = hashlib.sha256(b'').digest()
                before = f.verify()
                f.query('UPDATE request_facts SET wire=?', (changed,))
                command(f, 'recover', ['Reconciliation'], 1)
                assert f.verify() == before
                print('request_fixture', case, flush=True)
                continue
            command(f, 'recover', ['Ready'] if case == 'cancel' else ['Expired', 'Ready'])
            rows = f.query('SELECT wire FROM request_facts ORDER BY sequence')
            assert len(rows) == 2 and rows[1][0][88:104] == request_id
            assert rows[1][0][104] == (2 if case == 'cancel' else 3)
            before = f.verify()
            if case == 'remove_expiry':
                f.query("DELETE FROM request_facts WHERE kind=x'13'")
                command(f, 'recover', ['Reconciliation'], 1)
            else:
                command(f, 'recover', ['Ready'])
            assert f.verify() == before and len(f.rows()[0]) == 2
            assert not list((f.root / 'attempts').iterdir())
        print('request_fixture', case, flush=True)


if __name__ == '__main__':
    issuance_and_expiry()
