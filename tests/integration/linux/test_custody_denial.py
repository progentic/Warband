"""Run as root on a disposable systemd Linux host. Only the fixture parent uses root."""
import argparse
import contextlib
import errno
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import signal
import socket
import struct
import subprocess
import tempfile
import time
import uuid

STORE = bytes([1]) * 16
ZERO = bytes(32)
ROOT = Path(__file__).resolve().parents[3]
VECTORS = ROOT / 'docs/verification/adr0005-golden-vectors.json'


def sha(data):
    return hashlib.sha256(data).digest()


def emit(**event):
    print(json.dumps(event, sort_keys=True), flush=True)


def limits(pid):
    relative = Path(f'/proc/{pid}/cgroup').read_text().strip().split('::', 1)[1]
    group = Path('/sys/fs/cgroup') / relative.lstrip('/')
    return tuple(int((group / name).read_text()) for name in ('memory.max', 'memory.swap.max'))


def as_user(uid, fn):
    """A fresh client process gets real/effective/saved UID and GID, with no extra groups."""
    read_fd, write_fd = os.pipe()
    pid = os.fork()
    if pid == 0:
        try:
            os.close(read_fd)
            os.setgroups([])
            os.setgid(uid)
            os.setuid(uid)
            assert os.getresuid() == (uid,) * 3 and os.getgroups() == []
            assert limits('self') == (256*1024*1024, 0)
            result = fn()
            os.write(write_fd, result)
            os._exit(0)
        except BaseException as exc:
            os.write(write_fd, repr(exc).encode()[:2000])
            os._exit(1)
    os.close(write_fd)
    with os.fdopen(read_fd, 'rb') as pipe:
        result = pipe.read()
    _, status = os.waitpid(pid, 0)
    assert status == 0, (uid, result)
    return result


def request(root, endpoint, uid, op, payload, custodian):
    data = b'WBCR' + struct.pack('<HBI', 1, op, len(payload)) + payload

    def exchange():
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(12)
            conn.connect(str(root / 'endpoints' / endpoint))
            credentials = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
            assert struct.unpack('3i', credentials)[1] == custodian
            conn.sendall(data)
            conn.shutdown(socket.SHUT_WR)
            chunks = bytearray()
            while block := conn.recv(512):
                chunks.extend(block)
                assert len(chunks) <= 490
            return bytes(chunks)

    wire = as_user(uid, exchange)
    assert len(wire) in (151, 287, 354, 490), (op, len(wire))
    ver, echoed_op, status, length = struct.unpack_from('<HBHI', wire, 4)
    assert (wire[:4], ver, echoed_op, length) == (b'WBRS', 1, op, len(wire)-13)
    assert wire[13:45] == sha(b'warband.request.v1\0'+data)
    offset = 142 + 136*wire[141]
    tip, embedded = struct.unpack_from('<QB', wire, offset)
    frame = wire[offset+9:]
    assert embedded in (0, 1) and len(frame) == 203*embedded
    emit(op=op, uid=uid, endpoint=endpoint, status=status, tip=tip, receipt=wire[45:77].hex())
    return status, wire[45:77], wire[77:141], wire[142:offset], tip, frame


def denied(reply, storage=False):
    status, receipt, checkpoint, pending, tip, frame = reply
    assert status == (14 if storage else 15)
    assert (receipt == ZERO) == storage
    assert (checkpoint, pending, tip, frame) == (bytes(64), b'', 0, b'')
    return receipt


def filesystem_denials(root, runtime):
    for name in ('history', 'head'):
        path = root / 'data' / name
        assert path.is_file()
        for flags in (os.O_RDONLY, os.O_WRONLY):
            def try_open():
                try:
                    fd = os.open(path, flags)
                except OSError as exc:
                    return str(exc.errno).encode()
                os.close(fd)
                return b'opened'
            number = as_user(runtime, try_open)
            assert number == str(errno.EACCES).encode(), (path, number)
            emit(uid=runtime, path=name, flags=flags, errno=int(number))
    for path in (root/'data', root/'data'/'head', root/'endpoints'/'operator.sock'):
        def try_rename():
            try:
                path.rename(path.with_name('forbidden-replacement'))
            except OSError as exc:
                return str(exc.errno).encode()
            return b'renamed'
        assert as_user(runtime, try_rename) == b'13'
        emit(uid=runtime, rename=str(path.relative_to(root)), errno=errno.EACCES)


@contextlib.contextmanager
def service(root, binary, custodian, runtime, operator):
    unit = 'warband-test-' + uuid.uuid4().hex
    subprocess.run(['systemd-run', '--quiet', '--collect', '--service-type=exec',
                    '-p', 'MemoryMax=32M', '-p', 'MemorySwapMax=0', '--unit', unit,
                    '/usr/bin/setpriv', f'--reuid={custodian}', f'--regid={custodian}', '--clear-groups',
                    '--no-new-privs', str(binary), root.name, str(runtime), str(operator), STORE.hex()], check=True)
    try:
        pid = int(subprocess.check_output(['systemctl', 'show', '-p', 'MainPID', '--value', unit]))
        assert limits(pid) == (32*1024*1024, 0)
        # Stale socket names from a previous process cannot satisfy this probe.
        until = time.monotonic() + 12
        while time.monotonic() < until:
            if (root/'endpoints'/'operator.sock').is_socket():
                inodes = {os.readlink(p) for p in Path(f'/proc/{pid}/fd').iterdir()}
                if sum(i.startswith('socket:[') for i in inodes) >= 2:
                    break
            time.sleep(0.05)
        else:
            raise RuntimeError('custodian did not listen')
        yield pid
    except BaseException:
        subprocess.run(['journalctl', '--no-pager', '-n', '25', '-u', unit])
        raise
    finally:
        subprocess.run(['systemctl', 'stop', unit], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run(normal, fault):
    assert os.getuid() == 0 and limits('self') == (256*1024*1024, 0)
    # Use free numeric test identities; no persistent accounts or memberships.
    assigned = {p.pw_uid for p in pwd.getpwall()}
    custodian, runtime, operator, outsider = [u for u in range(50000, 60000) if u not in assigned][:4]
    vectors = json.loads(VECTORS.read_text())
    payload = bytes.fromhex(vectors['custody_tuple_hex'])
    enrollment = bytes.fromhex(vectors['enrollment_payload_hex'])
    epoch = bytes.fromhex(vectors['epoch_changes'][0]['request_payload_hex'])
    with tempfile.TemporaryDirectory(prefix='warband-3b-', dir='/var/lib') as tmp:
        root = Path(tmp)
        root.chmod(0o755)
        for name, owner, mode in [('data',custodian,0o700),('endpoints',custodian,0o755),('journal',operator,0o555)]:
            path = root / name
            path.mkdir()
            os.chown(path,owner,owner)
            path.chmod(mode)
        normal_path = Path(shutil.copy2(normal,root/'custodian'))
        fault_path = Path(shutil.copy2(fault,root/'fault-custodian'))
        def call(uid, admin, op, data):
            return request(root,'operator.sock' if admin else 'runtime.sock',uid,op,data,custodian)

        # First-create fault experiment on a separate history from the success case.
        with service(root,fault_path,custodian,runtime,operator):
            denied(call(runtime,True,4,enrollment),storage=True)
        history = root/'data'/'history'
        assert history.stat().st_size == 203
        retained = history.read_bytes()[-32:]
        with service(root,normal_path,custodian,runtime,operator):
            journal_entry = root/'journal'/'empty.db'
            journal_entry.touch()
            assert call(operator,True,4,enrollment)[0] == 16
            assert not (root/'data'/'head').exists()
            journal_entry.unlink()
            assert call(operator,True,4,enrollment)[0] == 0
            assert call(runtime,False,3,STORE+struct.pack('<QQ',1,0))[5][-32:] == retained
        history.rename(root/'fault-history')
        (root/'data'/'head').rename(root/'fault-head')
        receipts = []
        with service(root,normal_path,custodian,runtime,operator) as pid:
            receipts.append(denied(call(runtime,True,4,enrollment)))
            assert history.read_bytes()[-32:] == receipts[-1]
            assert not (root/'data'/'head').exists()
            os.kill(pid,signal.SIGKILL)
        with service(root,normal_path,custodian,runtime,operator):
            assert call(operator,True,4,enrollment)[0] == 0
            ok, pending_receipt, *_ = call(runtime,False,1,payload)
            assert ok == 0 and pending_receipt != ZERO
            assert call(runtime,False,1,payload)[1] == pending_receipt
            ok, committed_receipt, *_ = call(runtime,False,2,payload)
            assert ok == 0 and committed_receipt != ZERO
            assert call(runtime,False,2,payload)[1] == committed_receipt
            receipts.append(denied(call(runtime,True,5,epoch)))
            for op, data in [(1,payload),(2,payload),(3,STORE+struct.pack('<QQ',1,0)),(4,enrollment),(5,epoch)]:
                receipts.append(denied(call(outsider,op>=4,op,data)))
            filesystem_denials(root,runtime)
        with service(root,normal_path,custodian,runtime,operator):
            cursor = 0
            for i,receipt in enumerate(receipts):
                verified = call(runtime,False,3,STORE+struct.pack('<QQ',1,cursor))
                status, _, cp, pending, tip, frame = verified
                assert status == 0 and cp == STORE+struct.pack('<QQ',1,1)+payload[72:104] and not pending
                ordinal = struct.unpack_from('<Q',frame,11)[0]
                assert cursor < ordinal <= tip and frame[-32:] == receipt
                assert sha(b'warband.custody.record.v1\0'+frame[:-32]) == receipt
                assert frame[6] == 5 and frame[83+63] == 1
                uid,gid,pid = struct.unpack_from('<QQQ',frame,83+64)
                assert uid == gid == (runtime if i < 2 else outsider) and pid > 0
                cursor = ordinal
            assert not call(runtime,False,3,STORE+struct.pack('<QQ',1,cursor))[5]
            unchanged = history.read_bytes()
            head_path = root/'data'/'head'
            good = head_path.read_bytes()
            head_path.write_bytes(good[:-1])
            assert call(runtime,False,3,STORE+struct.pack('<QQ',1,0))[0] == 9
            assert head_path.read_bytes() == good[:-1] and history.read_bytes() == unchanged
            head_path.write_bytes(good)
            assert call(operator,True,5,epoch)[0] == 0
            replay = call(operator,True,5,epoch)
            assert replay[0] == 0 and replay[1] != ZERO
    emit(result='pass',custodian_uid=custodian,runtime_uid=runtime,operator_uid=operator,unlisted_uid=outsider)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('normal', type=Path)
    parser.add_argument('fault', type=Path)
    args = parser.parse_args()
    run(args.normal,args.fault)
