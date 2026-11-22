"""Real-UID reconciliation and post-COMMIT process recovery. Run in the same disposable scope as the denial harness."""
import contextlib
import fcntl
import json
import os
import multiprocessing
import socket
import select
from pathlib import Path
import pwd
import shutil
import signal
import sqlite3
import struct
import subprocess
import tempfile
import time

from test_custody_denial import STORE, VECTORS, ZERO, as_user, denied, emit, limits, request, service, sha

OUT = Path("out/linux_amd64")
def LE(value):
    return struct.pack("<Q", value)
ENROLL = bytes.fromhex(json.loads(VECTORS.read_text())["enrollment_payload_hex"])


def event_and_pledge(previous, frame, recorded_time=456):
    body = (b'WBEV' + struct.pack('<HH', 1, 8) + STORE + struct.pack('<QQQHHI', 1, 1, recorded_time, 5, 1, 36)
            + bytes.fromhex('070d0000') + sha(frame))
    digest = sha(b'warband.event.v1\0' + body)
    head = sha(b'warband.link.v1\0' + STORE + LE(1) + LE(1) + previous + digest)
    pledge = STORE + LE(1) + LE(0) + previous + LE(1) + head + digest
    return body + previous, pledge


class Fixture:
    def __init__(self, root, users):
        self.root = root
        self.custodian, self.runtime, self.operator = users
        self.db = root/'journal'/'active.db'
        self.epoch = 1
        self.archives = []

    def call(self, op, payload, *, denied_admin=False):
        uid = self.operator if op >= 4 and not denied_admin else self.runtime
        endpoint = 'operator.sock' if op >= 4 else 'runtime.sock'
        return request(self.root, endpoint, uid, op, payload, self.custodian)

    def verify(self, cursor=0):
        result = self.call(3, STORE + LE(self.epoch) + LE(cursor))
        assert result[0] == 0
        return result

    def provision(self):
        subprocess.run([self.root/'provision', self.db], check=True)
        os.chown(self.db,self.runtime,self.runtime)

    def run(self, expected, retry=None, allow=True, uid=None):
        args = [self.root/'importer', self.db, self.root/'endpoints'/'runtime.sock',
                str(self.custodian if uid is None else uid), STORE.hex(), str(self.epoch),
                str(retry[0]) if retry else '0', retry[1].hex() if retry else '-', *self.archives]
        def invoke():
            p = subprocess.run(args, capture_output=True, timeout=65)
            return json.dumps([p.returncode,p.stdout.decode().strip(),p.stderr.decode()]).encode()
        rc, output, error = json.loads(as_user(self.runtime, invoke))
        assert (rc,output.split()[0]) == (0 if allow else 1,expected), (rc,output,error)
        emit(outcome=output, progress_permitted=rc==0)
        return output

    def query(self, sql, params=()):
        with contextlib.closing(sqlite3.connect(self.db)) as conn, conn:
            return list(conn.execute(sql,params))

    def rows(self):
        return [self.query('SELECT * FROM '+name) for name in ('events','denial_imports','import_watermarks')]


@contextlib.contextmanager
def fixture(*, measure=False, proof_variant=None, fresh=False):
    existing = {p.pw_uid for p in pwd.getpwall()}
    users = [u for u in range(50000,60000) if u not in existing][:3]
    with tempfile.TemporaryDirectory(prefix='warband-import-',dir='/var/lib') as tmp:
        root = Path(tmp)
        root.chmod(0o755)
        for name,uid,mode in [('endpoints',users[0],0o755),('data',users[0],0o700),('journal',users[2],0o555)]:
            path = root/name
            path.mkdir()
            os.chown(path,uid,uid)
            path.chmod(mode)
        for name,path in [('custodian',OUT/'custodian/normal/custodian'),('importer',OUT/'reconcile/reconcile-custody'),
                          ('provision',OUT/'provision-store')]:
            shutil.copy2(path,root/name)
        f = Fixture(root,users)
        log = root/'capacity.log' if measure else None
        if measure:
            shutil.copy2(OUT/'capacity/custodian',root/'custodian')
            log.touch(mode=0o600)
        if proof_variant and proof_variant.startswith(('append-','publish-err-')):
            log = root/'storage.log'
        first_service = root/'custodian'
        if proof_variant is not None:
            first_service = shutil.copy2(OUT/'custodian'/proof_variant/'custodian', root/'proof-custodian')
        with service(root,first_service,*users,stderr_path=log) as f.custodian_pid:
            if fresh:
                yield f, None, None
                return
            receipt = None if measure else denied(f.call(4,ENROLL,denied_admin=True))
            assert f.call(4,ENROLL)[0] == 0
            os.chown(root/'journal',users[1],users[1])
            (root/'journal').chmod(0o700)
            f.provision()
            _,_,cp,_,_,frame = f.verify()
            if measure:
                assert not frame
            else:
                assert frame[-32:] == receipt
            yield f, cp[32:], frame


def craft(f, frame, event):
    ordinal = frame[11:19]
    with contextlib.closing(sqlite3.connect(f.db)) as conn, conn:
        conn.execute('PRAGMA foreign_keys=ON')
        conn.execute('INSERT INTO events VALUES(?,?,?,?)',(STORE,LE(1),LE(1),event))
        conn.execute('INSERT INTO denial_imports VALUES(?,?,?,?,?)',(STORE,ordinal,frame[-32:],LE(1),LE(1)))
        conn.execute('INSERT INTO import_watermarks VALUES(?,?)',(STORE,ordinal))


def restart(state):
    with fixture() as (f, genesis, frame):
        event, pledge = event_and_pledge(genesis,frame)
        if state != 'UnattestedTail':
            assert f.call(1,pledge)[0] == 0
        if state != 'PendingEventMissing':
            craft(f,frame,event)
        if state in ('ConfirmedResponsePending','IntegrityFault'):
            assert f.call(2,pledge)[0] == 0
        if state == 'IntegrityFault':
            f.query('DELETE FROM import_watermarks')
        if state == 'PendingConfirmation':
            changed = bytearray(event)
            changed[40] ^= 1  # Persisted recorded time now disagrees with the complete pledge.
            f.query('UPDATE events SET canonical_event=?',(changed,))
            pending_state = f.verify()
            f.run('IntegrityFault',allow=False)
            assert f.verify() == pending_state
            f.query('UPDATE events SET canonical_event=?',(event,))
        before, custody = f.rows(), f.verify()
        can_progress = state in ('ConfirmedResponsePending','PendingConfirmation')
        retry = (1,frame[-32:]) if state == 'ConfirmedResponsePending' else None
        output = f.run(state,retry,can_progress)
        if retry:
            assert output.split()[1:] == [STORE.hex(),'1','1']
        assert f.rows() == before
        after = f.verify()
        if state == 'PendingConfirmation':
            assert after[2] == STORE+LE(1)+LE(1)+pledge[72:104] and not after[3]
            assert after[4] == custody[4]+1
            f.run('Ready')
            assert f.verify() == after and f.rows() == before
        else:
            assert after == custody


def kill_importer(f, stop, diagnostics=None):
    binary = shutil.copy2(OUT/'reconcile'/f'reconcile-custody-stop-{stop}', f.root/'fault-importer')
    args = [binary, f.db, f.root/'endpoints/runtime.sock', str(f.custodian), STORE.hex(), '1', '0', '-']
    with subprocess.Popen(args, user=f.runtime, group=f.runtime, extra_groups=[], stdout=subprocess.PIPE, stderr=diagnostics) as child:
        try:
            deadline = time.monotonic() + 65
            while time.monotonic() < deadline:
                event = os.waitid(os.P_PID, child.pid, os.WSTOPPED | os.WEXITED | os.WNOHANG | os.WNOWAIT)
                if event is not None:
                    assert (event.si_pid, event.si_code, event.si_status) == (child.pid, os.CLD_STOPPED, signal.SIGSTOP), event
                    break
                time.sleep(0.01)
            else:
                raise AssertionError(f'importer {child.pid} did not reach its {stop} stop')
        finally:
            child.kill()
            status = child.wait(timeout=10)
        assert status == -signal.SIGKILL and child.stdout.read() == b''
    return child.pid, status


def import_process_kill(stop):
    with fixture() as (f, genesis, frame):
        before = f.verify()
        assert f.rows() == [[], [], []] and not before[3]
        pid, status = kill_importer(f, stop)

        # Independent reads after death. Derive the complete pledge from the durable event.
        rows = f.rows()
        assert [len(table) for table in rows] == [1, 1, 1]
        body = rows[0][0][3]
        recorded_time, = struct.unpack_from('<Q', body, 40)
        canonical, pledge = event_and_pledge(genesis, frame, recorded_time)
        ref = (STORE, LE(1), LE(1))
        ordinal = frame[11:19]
        assert rows == [[(*ref, canonical)], [(STORE, ordinal, frame[-32:], *ref[1:])], [(STORE, ordinal)]]
        replay = shutil.copy2(OUT/'reconcile/replay-noop', f.root/'replay-noop')

        replay_case = 'before_ack_replay' if stop == 'before-ack' else 'post_commit_replay'

        def check_replay(stage, custody, expected_tip, expected_journal, expected_outstanding):
            result = subprocess.run([replay, f.db, f.root/'endpoints/runtime.sock', str(f.custodian),
                                     STORE.hex(), str(f.epoch)], user=f.runtime, group=f.runtime,
                                    extra_groups=[], capture_output=True, text=True, timeout=65)
            # The only event is audit-only. Exact stdout also requires zero task rows.
            journal = f'Journal {expected_journal} OutstandingReceipts {expected_outstanding}'
            assert result.returncode == 0 and result.stdout.splitlines() == [journal], (result.stdout, result.stderr)
            assert custody[4] == expected_tip and f.verify() == custody and f.rows() == rows
            emit(case=replay_case, stage=stage, tip=custody[4], output=result.stdout.strip())

        if stop == 'before-ack':
            confirmed = f.verify()
            assert confirmed[2] == b''.join(ref) + pledge[72:104] and not confirmed[3]
            check_replay('after_kill', confirmed, 4, 'Ready', 0)

            store, receipt_ordinal, record_hash, epoch, sequence = rows[1][0]
            retry = (int.from_bytes(receipt_ordinal, 'little'), record_hash)
            result = f.run('ConfirmedResponsePending', retry)
            expected_ref = [store.hex(), str(int.from_bytes(epoch, 'little')), str(int.from_bytes(sequence, 'little'))]
            assert result.split() == ['ConfirmedResponsePending', *expected_ref], result
            assert f.rows() == rows and f.verify() == confirmed
            assert f.run('Ready') == 'Ready'
            assert f.rows() == rows and f.verify() == confirmed
            check_replay('ordinary_restart', confirmed, 4, 'Ready', 0)
            emit(case='before_ack_process_kill', pid=pid, stopped='SIGSTOP', reaped=status,
                 stdout_bytes=0, tip=confirmed[4], retry_result=result, receipt_hash=record_hash.hex())
            return

        pending = f.verify()
        tip = pending[4]
        assert pending[2] == before[2] and pending[3] == pledge and tip == before[4] + 1
        check_replay('after_kill', pending, 3, 'PendingConfirmation', 1)
        f.run('PendingConfirmation')
        confirmed = f.verify()
        assert confirmed[2] == STORE + LE(1) + LE(1) + pledge[72:104] and not confirmed[3]
        assert confirmed[4] == tip + 1 and f.rows() == rows
        check_replay('first_restart', confirmed, 4, 'Ready', 0)
        f.run('Ready')
        second = f.verify()
        assert second == confirmed and f.rows() == rows
        check_replay('second_restart', second, 4, 'Ready', 0)
        emit(case='post_commit_process_kill', pid=pid, stopped='SIGSTOP', reaped=status,
             pending_tip=tip, confirmed_tip=confirmed[4], second_tip=second[4],
             receipt_hash=frame[-32:].hex(), watermark=int.from_bytes(ordinal, 'little'))


def kill_custodian_during_import(f, args, user, edge):
    pid = f.custodian_pid
    pidfd = os.pidfd_open(pid)
    try:
        with subprocess.Popen([f.root/'importer', *args, '0', '-'], **user,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as importer:
            try:
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if 'State:\tT (stopped)' in Path(f'/proc/{pid}/status').read_text().splitlines():
                        break
                    assert importer.poll() is None, ('importer exited before stop', edge)
                    time.sleep(0.01)
                else:
                    raise AssertionError(('publication stop not observed', edge, pid))
                assert importer.poll() is None
            finally:
                signal.pidfd_send_signal(pidfd, signal.SIGKILL)
            output, error = importer.communicate(timeout=35)
            assert (importer.returncode, output.splitlines()) == (1, ['AttestationUncertain']), (output, error)
    finally:
        os.close(pidfd)
    return output.strip()


def confirm_kill(phase, edge):
    with fixture(proof_variant=f'{phase}-{edge}') as (f, genesis, frame):
        head = f.root/'data/head'
        temporary = f.root/'data/head.tmp'
        history = f.root/'data/history'
        old_head, old_history = head.read_bytes(), history.read_bytes()
        baseline = f.verify()
        assert baseline[3:5] == (b'', 2) and f.rows() == [[], [], []]
        old_prefix = b'WBHD' + struct.pack('<H', 1) + STORE + LE(1) + LE(0) + genesis + old_history[-32:]
        assert old_head == old_prefix + sha(b'warband.head.v1\0' + old_prefix)
        args = [f.db, f.root/'endpoints/runtime.sock', str(f.custodian), STORE.hex(), '1']
        user = dict(user=f.runtime, group=f.runtime, extra_groups=[])
        output = kill_custodian_during_import(f, args, user, edge)

        # Reconstruct both appended frames and the head before recovery can touch any file.
        rows = f.rows()
        assert [len(table) for table in rows] == [1, 1, 1]
        recorded_time, = struct.unpack_from('<Q', rows[0][0][3], 40)
        event, pledge = event_and_pledge(genesis, frame, recorded_time)
        ref = STORE, LE(1), LE(1)
        ordinal = frame[11:19]
        assert rows == [[(*ref, event)], [(STORE, ordinal, frame[-32:], *ref[1:])], [(STORE, ordinal)]]
        retained = old_history
        for kind, position in ((1, 3), (2, 4)):
            header = b'WBCH' + struct.pack('<HBIQ', 1, kind, len(pledge), position) + retained[-32:]
            record = header + sha(b'warband.custody.header.v1\0' + header) + pledge
            retained += record + sha(b'warband.custody.record.v1\0' + record)
        pending_history, committed = retained[:-251], retained[-251:]
        captured = history.read_bytes()
        assert captured.startswith(pending_history)
        suffix = captured[len(pending_history):]
        assert len(suffix) <= len(committed) and suffix == committed[:len(suffix)]
        published = head.read_bytes()
        if not suffix:
            recovery = 'PendingConfirmation'
        elif suffix == committed:
            recovery = 'HeadPublicationPending' if published == old_head else 'Consistent'
        else:
            recovery = 'TornFinalRecord'
        receipt = retained[-32:]
        checkpoint = b''.join(ref) + pledge[72:104]
        prefix = b'WBHD' + struct.pack('<H', 1) + checkpoint + receipt
        new_head = prefix + sha(b'warband.head.v1\0' + prefix)
        assert old_head != new_head
        if phase == 'committed':
            emit(case='committed_capture', edge=edge, classified=recovery, suffix_length=len(suffix),
                 suffix_sha256=sha(suffix).hex(), published_sequence=int.from_bytes(published[30:38], 'little'))
            assert len(suffix) == (0, 250, 251, 251)[edge-1]
        else:
            assert suffix == committed
        temp_expected = phase == 'publish' and edge <= 2
        assert published == (old_head if phase == 'committed' or temp_expected else new_head)
        if temp_expected:
            assert temporary.read_bytes() == new_head
        else:
            assert not temporary.exists()

        replay = shutil.copy2(OUT/'reconcile/replay-noop', f.root/'replay-noop')
        def run_replay():
            return subprocess.run([replay, *args], **user, capture_output=True, text=True, timeout=65)
        blocked = run_replay()
        assert (blocked.returncode, blocked.stdout) == (1, ''), (blocked.stdout, blocked.stderr)
        with service(f.root, f.root/'custodian', f.custodian, f.runtime, f.operator):
            verified = f.verify()
            startup_tip = verified[4]
            assert not temporary.exists() and f.rows() == rows
            if recovery in ('PendingConfirmation', 'TornFinalRecord'):
                assert verified[2:5] == (baseline[2], pledge, 3)
                assert head.read_bytes() == old_head and history.read_bytes() == pending_history
                pending = run_replay()
                assert (pending.returncode, pending.stdout.splitlines()) == (0, ['Journal PendingConfirmation OutstandingReceipts 1'])
                assert f.run('PendingConfirmation') == 'PendingConfirmation'
                verified = f.verify()
            assert verified[2:5] == (checkpoint, b'', 4)
            assert history.read_bytes() == retained and f.rows() == rows
            assert head.read_bytes() == new_head and not temporary.exists()
            if phase == 'committed' and startup_tip == 4:
                assert f.run('Ready') == 'Ready'
                assert history.read_bytes() == captured and f.verify() == verified and f.rows() == rows
            exact = f.call(2, pledge)
            assert exact[:5] == (0, receipt, checkpoint, b'', 4)
            ready = run_replay()
            assert (ready.returncode, ready.stdout.splitlines()) == (0, ['Journal Ready OutstandingReceipts 0'])
            assert history.read_bytes() == retained and head.read_bytes() == new_head
            assert f.verify() == verified and f.rows() == rows
            emit(case='publication_kill' if phase == 'publish' else 'committed_kill', edge=edge, custodian_pid=f.custodian_pid, caller=output.strip(),
                 published_before='old' if published == old_head else 'new', temp_before=temp_expected, startup_tip=startup_tip,
                 replay_before_exit=blocked.returncode, recovered_tip=verified[4],
                 exact_confirm_receipt=receipt.hex(), replay_after=ready.stdout.strip())


def prepare_kill(prefix_length):
    pre_send = prefix_length is None
    variant = None if pre_send else f'pending-{prefix_length}'
    with fixture(proof_variant=variant) as (f, _, _):
        # Establish the writing connection's persistent journal mode before sampling.
        assert f.query('PRAGMA journal_mode=WAL') == [('wal',)]
        baseline = f.verify()
        assert baseline[3:5] == (b'', 2) and f.rows() == [[], [], []]
        history, head = f.root/'data/history', f.root/'data/head'
        old_history, old_head, database = history.read_bytes(), head.read_bytes(), f.db.read_bytes()
        replay = shutil.copy2(OUT/'reconcile/replay-noop', f.root/'replay-noop')
        args = [f.db, f.root/'endpoints/runtime.sock', str(f.custodian), STORE.hex(), '1']
        user = dict(user=f.runtime, group=f.runtime, extra_groups=[])

        def check_baseline():
            result = subprocess.run([replay, *args], **user, capture_output=True, text=True, timeout=65)
            assert (result.returncode, result.stdout.splitlines()) == (0, ['Journal Ready OutstandingReceipts 1'])
            assert f.verify() == baseline and f.rows() == [[], [], []]
            assert history.read_bytes() == old_history and head.read_bytes() == old_head
            assert f.db.read_bytes() == database
            return result.stdout.strip()

        check_baseline()
        if pre_send:
            pid, status = kill_importer(f, 'before-prepare')
            journal = check_baseline()
            emit(case='prepare_kill', stop='before_send', importer_pid=pid, reaped=status,
                 stdout_bytes=0, suffix_length=0, suffix_digest=sha(b'').hex(), tip=2, replay=journal)
            return

        caller = kill_custodian_during_import(f, args, user, variant)
        retained = history.read_bytes()
        header = b'WBCH' + struct.pack('<HBIQ', 1, 1, 136, 3) + old_history[-32:]
        prefix = header + sha(b'warband.custody.header.v1\0' + header)
        assert len(prefix) == 83 and retained == old_history + prefix[:prefix_length]
        suffix = retained[len(old_history):]
        assert head.read_bytes() == old_head and f.db.read_bytes() == database and f.rows() == [[], [], []]
        blocked = subprocess.run([replay, *args], **user, capture_output=True, text=True, timeout=65)
        assert (blocked.returncode, blocked.stdout) == (1, '')
        assert history.read_bytes() == retained and head.read_bytes() == old_head
        with service(f.root, f.root/'custodian', f.custodian, f.runtime, f.operator):
            journal = check_baseline()
        emit(case='prepare_kill', stop=variant, custodian_pid=f.custodian_pid, caller=caller,
             suffix_length=len(suffix), suffix=suffix.hex(), suffix_digest=sha(suffix).hex(),
             retained_prefix_digest=sha(old_history).hex(), tip=2, replay=journal)


def inspect_wal(path):
    raw = path.read_bytes() if path.exists() else b''
    info = dict(present=path.exists(), size=len(raw), page_size=0, valid_frames=0, last_commit=0)
    if not raw:
        return info
    magic, version, page_size = struct.unpack_from('>III', raw)
    assert magic in (0x377f0682, 0x377f0683) and version == 3007000
    assert 512 <= page_size <= 65536 and page_size & (page_size-1) == 0
    order = '<II' if magic == 0x377f0682 else '>II'

    def checksum(data, a=0, b=0):
        for x, y in struct.iter_unpack(order, data):
            a = (a+x+b) & 0xffffffff
            b = (b+y+a) & 0xffffffff
        return a, b

    sums = checksum(raw[:24])
    assert sums == struct.unpack_from('>II', raw, 24)
    info.update(page_size=page_size, salts=raw[16:24].hex())
    stride = 24+page_size
    for start in range(32, len(raw)-stride+1, stride):
        h = raw[start:start+24]
        page, commit_size = struct.unpack_from('>II', h)
        sums = checksum(h[:8]+raw[start+24:start+stride], *sums)
        if not page or h[8:16] != raw[16:24] or sums != struct.unpack_from('>II', h, 16):
            break
        info['valid_frames'] += 1
        if commit_size:
            info['last_commit'] = info['valid_frames']
    info['unvalidated_trailing_bytes'] = len(raw)-32-info['valid_frames']*stride
    return info


def transaction_result(f, bundle, genesis, receipt, verified, pledge_valid):
    # Open all sidecars together on a disposable copy. Keep the capture pristine.
    with tempfile.TemporaryDirectory(dir=f.root) as tmp:
        journal = shutil.copytree(bundle/'journal', Path(tmp)/'journal')
        with contextlib.closing(sqlite3.connect(journal/'active.db')) as db:
            db.execute('BEGIN')
            rows = [list(db.execute('SELECT * FROM '+table)) for table in
                    ('events', 'denial_imports', 'import_watermarks')]
    if not pledge_valid:
        return 'IntegrityFault', rows
    if rows == [[], [], []]:
        return 'PendingEventMissing', rows
    if [len(r) for r in rows] == [1, 1, 1]:
        wire = rows[0][0][3]
        if isinstance(wire, bytes) and len(wire) == 124:
            event, pledge = event_and_pledge(genesis, receipt, struct.unpack_from('<Q', wire, 40)[0])
            ref = STORE, LE(1), LE(1)
            ordinal = receipt[11:19]
            exact = [[(*ref, event)], [(STORE, ordinal, receipt[-32:], *ref[1:])], [(STORE, ordinal)]]
            if rows == exact and verified[3] == pledge:
                return 'PendingConfirmation', rows
    return 'IntegrityFault', rows


def capture_files(f, bundle, *, include_tmp=False):
    # No SQLite connection or recovery probe between reap and this quiescent copy.
    files = ['data/history', 'data/head', 'journal/active.db']
    sidecars = {}
    if include_tmp and (f.root/'data/head.tmp').exists():
        files.append('data/head.tmp')
    for ext in ('-wal', '-shm', '-journal'):
        name = 'journal/active.db'+ext
        sidecars[name] = (f.root/name).exists()
        if sidecars[name]:
            files.append(name)
    hashes, ownership = {}, {}
    for name in files:
        src, dst = f.root/name, bundle/name
        dst.parent.mkdir(exist_ok=True)
        st = src.stat()
        ownership[name] = [st.st_uid, st.st_gid, oct(st.st_mode & 0o777)]
        hashes[name] = sha(src.read_bytes()).hex()
        shutil.copyfile(src, dst)
        assert sha(dst.read_bytes()).hex() == hashes[name]
    return hashes, ownership, sidecars


def seal_capture(bundle, hashes, meta):
    manifest = bundle/'capture.json'
    manifest.write_text(json.dumps(meta, sort_keys=True, indent=2)+'\n')
    hashes[manifest.name] = sha(manifest.read_bytes()).hex()
    sums = bundle/'SHA256SUMS'
    sums.write_text(''.join(f'{digest}  {name}\n' for name, digest in sorted(hashes.items())))
    bundle.chmod(0o755)  # Hosted artifact collection runs as the unprivileged runner.
    inventory = sha(sums.read_bytes()).hex()
    return inventory


def receipt_transaction_kill(stop):
    with fixture() as (f, genesis, receipt):
        assert f.query('PRAGMA journal_mode=WAL') == [('wal',)]
        baseline = f.verify()
        assert baseline[3:5] == (b'', 2) and f.rows() == [[], [], []]
        history, head = f.root/'data/history', f.root/'data/head'
        old_history, old_head = history.read_bytes(), head.read_bytes()
        source = subprocess.check_output(['git', '-c', f'safe.directory={Path.cwd()}', 'rev-parse', 'HEAD'],
                                         text=True).strip()
        point2 = stop == 'after-prepare'
        parent = OUT/('point2-rehearsal' if point2 else 'point3-transactions')
        parent.mkdir(exist_ok=True)
        bundle = Path(tempfile.mkdtemp(dir=parent, prefix='capture-'))
        baseline_wal = inspect_wal(Path(str(f.db)+'-wal'))
        diagnostics = f.root/'importer-stderr'
        with diagnostics.open('wb') as stream:
            pid, status = kill_importer(f, stop, stream)

        hashes, ownership, sidecars = capture_files(f, bundle)
        retained = (bundle/'data/history').read_bytes()
        pending = retained[len(old_history):]
        header = b'WBCH' + struct.pack('<HBIQ', 1, 1, 136, 3) + old_history[-32:]
        pledge = pending[83:-32]
        ref = STORE + LE(1) + LE(1)
        verified = f.verify()
        pledge_valid = (retained.startswith(old_history) and len(pending) == 251
                        and pending[:83] == header + sha(b'warband.custody.header.v1\0' + header)
                        and pending[-32:] == sha(b'warband.custody.record.v1\0' + pending[:-32])
                        and pledge[:72] == STORE + LE(1) + LE(0) + genesis + LE(1)
                        and pledge[72:104] == sha(b'warband.link.v1\0' + ref + genesis + pledge[104:])
                        and (bundle/'data/head').read_bytes() == old_head
                        and baseline[2] == STORE + LE(1) + LE(0) + genesis
                        and verified[2:] == (baseline[2], pledge, 3, receipt))
        wal = inspect_wal(bundle/'journal/active.db-wal')
        outcome, rows = transaction_result(f, bundle, genesis, receipt, verified, pledge_valid)
        witness = dict(line.split() for line in diagnostics.read_text().splitlines())
        counts = [len(table) for table in rows]
        emit(case='captured_transaction', stop=stop, observed=outcome, rows=counts, wal=wal)

        meta = dict(source=source, host=os.uname().nodename, kernel=os.uname().release, arch=os.uname().machine,
                    pending_ref=ref.hex(), tip=3, pending_record_hash=pending[-32:].hex(),
                    receipt_ordinal=int.from_bytes(receipt[11:19], 'little'), receipt_hash=receipt[-32:].hex(),
                    sidecars=sidecars, file_uid_gid_mode=ownership, runtime_uid=f.runtime,
                    operator_uid=f.operator, custodian_uid=f.custodian, stop=stop, observed=outcome,
                    baseline_wal=baseline_wal, wal=wal, rows=counts, hook=witness,
                    sizes={name:(bundle/name).stat().st_size for name in hashes})
        inventory = seal_capture(bundle, hashes, meta)
        emit(capture=str(bundle), stop=stop, inventory_sha256=inventory)
        expected = 'PendingConfirmation' if stop == 'wal-commit' else 'PendingEventMissing'
        assert outcome == expected, (outcome, expected, bundle)
        if stop == 'wal-commit':
            assert 0 < wal['last_commit'] == wal['valid_frames'] == int(witness['wal_frames']) < int(witness['wal_threshold'])
            assert baseline_wal['valid_frames'] == 0 and wal['unvalidated_trailing_bytes'] == 0
        else:
            assert not witness and wal['last_commit'] == baseline_wal['last_commit'] == 0
        replay = shutil.copy2(OUT/'reconcile/replay-noop', f.root/'replay-noop')
        def check_replay(readiness, outstanding):
            result = subprocess.run([replay, f.db, f.root/'endpoints/runtime.sock', str(f.custodian), STORE.hex(), '1'],
                                    user=f.runtime, group=f.runtime, extra_groups=[], capture_output=True, text=True, timeout=65)
            assert (result.returncode, result.stdout.splitlines()) == (0, [f'Journal {readiness} OutstandingReceipts {outstanding}'])
            return result.stdout.strip()

        replay_before = check_replay(outcome, 1)
        assert f.rows() == rows and f.verify() == verified
        restarts = []
        if outcome == 'PendingEventMissing':
            for _ in range(2):
                restarts.append(f.run(outcome, allow=False))
                assert restarts[-1] == outcome and f.verify() == verified and f.rows() == rows
                assert history.read_bytes() == retained and head.read_bytes() == old_head
            replay_after = check_replay(outcome, 1)
            assert f.verify() == verified and f.rows() == rows and history.read_bytes() == retained and head.read_bytes() == old_head
        else:
            restarts.append(f.run(outcome))
            confirmed = f.verify()
            assert confirmed[2:5] == (ref+pledge[72:104], b'', 4) and f.rows() == rows
            committed_history, committed_head = history.read_bytes(), head.read_bytes()
            restarts.append(f.run('Ready'))
            replay_after = check_replay('Ready', 0)
            assert f.verify() == confirmed and f.rows() == rows
            assert history.read_bytes() == committed_history and head.read_bytes() == committed_head
        emit(case='durable_prepare_kill' if point2 else 'sqlite_commit_kill', stop=stop, importer_pid=pid,
             reaped=status, stdout_bytes=0, tip=3, restarts=restarts, replay=replay_before, replay_after=replay_after,
             bundle=str(bundle), inventory_sha256=inventory)


def capture_storage_run(f, variant, mode, group):
    fd = os.pidfd_open(f.custodian_pid)
    try:
        caller = 'Ready' if mode==1 else 'AttestationUncertain'
        assert f.run(caller,allow=mode==1) == caller
        if mode!=1:
            poller = select.poll()
            poller.register(fd,select.POLLIN)
            assert poller.poll(5000), 'faulted custodian did not exit'
    finally:
        os.close(fd)

    parent = OUT/group
    parent.mkdir(exist_ok=True)
    bundle = Path(tempfile.mkdtemp(dir=parent,prefix=variant+'-'))
    hashes, owners, sidecars = capture_files(f,bundle,include_tmp=group=='publish-error')
    calls = (f.root/'storage.log').read_text().splitlines()
    meta = dict(variant=variant,caller=caller,calls=calls,sidecars=sidecars,file_uid_gid_mode=owners,
                host=os.uname().nodename,kernel=os.uname().release,source=subprocess.check_output(
                    ['git','-c',f'safe.directory={Path.cwd()}','rev-parse','HEAD'],text=True).strip())
    if group=='publish-error':
        meta['head_tmp_present'] = 'data/head.tmp' in hashes
    inventory = seal_capture(bundle,hashes,meta)
    return bundle, calls, caller, inventory


def append_fault(kind, mode):
    variant = f'append-{kind}-{mode}'
    with fixture(proof_variant=variant) as (f, genesis, denial):
        history, head = f.root/'data/history', f.root/'data/head'
        base, old_head = history.read_bytes(), head.read_bytes()
        assert f.verify()[3:5] == (b'', 2) and f.rows() == [[], [], []]
        bundle,calls,caller,inventory = capture_storage_run(f,variant,mode,'append-error')
        emit(append_capture=variant,bundle=str(bundle),inventory_sha256=inventory,calls=calls)
        prefix = 83 if kind==1 else 250
        first = f'append_write 251 {prefix}'
        remainder = 251-prefix
        if mode==3:
            assert calls == ['append_write 251 251','append_fsync -1 EIO'],calls
        else:
            last = str(remainder) if mode==1 else '-1 ENOSPC'
            assert calls == [first,f'append_write {remainder} {last}'],calls
        with tempfile.TemporaryDirectory(dir=f.root) as tmp:
            db = shutil.copytree(bundle/'journal',Path(tmp)/'journal')/'active.db'
            with contextlib.closing(sqlite3.connect(db)) as conn:
                conn.execute('BEGIN')
                rows = [list(conn.execute('SELECT * FROM '+t)) for t in ('events','denial_imports','import_watermarks')]
        retained = (bundle/'data/history').read_bytes()
        published = (bundle/'data/head').read_bytes()
        assert retained.startswith(base)
        tail = retained[len(base):]
        ref = STORE,LE(1),LE(1)
        if rows == [[],[],[]]:
            assert published == old_head
            hdr = b'WBCH'+struct.pack('<HBIQ',1,1,136,3)+base[-32:]
            if tail == hdr+sha(b'warband.custody.header.v1\0'+hdr):
                state, tip, startup_history, outstanding = 'Ready',2,base,1
                expected_pledge = b''
            else:
                pledge = tail[83:-32]
                assert len(pledge)==136 and pledge[:72]==STORE+LE(1)+LE(0)+genesis+LE(1)
                assert pledge[72:104]==sha(b'warband.link.v1\0'+b''.join(ref)+genesis+pledge[104:])
                assert tail == admin_frame(1,pledge,3,base[-32:])
                state, tip, startup_history, outstanding = 'PendingEventMissing',3,retained,1
                expected_pledge = pledge
            startup_head = old_head
        else:
            assert [len(t) for t in rows]==[1,1,1]
            timestamp, = struct.unpack_from('<Q',rows[0][0][3],40)
            event, pledge = event_and_pledge(genesis,denial,timestamp)
            assert rows == [[(*ref,event)],[(STORE,denial[11:19],denial[-32:],*ref[1:])],[(STORE,denial[11:19])]]
            pending = admin_frame(1,pledge,3,base[-32:])
            committed = admin_frame(2,pledge,4,pending[-32:])
            cp = b''.join(ref)+pledge[72:104]
            body = b'WBHD'+struct.pack('<H',1)+cp+committed[-32:]
            new_head = body+sha(b'warband.head.v1\0'+body)
            if tail == pending+committed[:250]:
                assert published == old_head
                state, tip, startup_history, outstanding = 'PendingConfirmation',3,base+pending,1
                expected_pledge, startup_head = pledge, old_head
            else:
                assert tail == pending+committed and published in (old_head,new_head)
                state, tip, startup_history, outstanding = 'Ready',4,retained,0
                expected_pledge, startup_head = b'',new_head
        assert (state,tip) == {(1,1):('Ready',4),(2,1):('Ready',4),(1,2):('Ready',2),
                               (2,2):('PendingConfirmation',3),(1,3):('PendingEventMissing',3),(2,3):('Ready',4)}[kind,mode]
        assert published == (startup_head if mode==1 else old_head)
        replay = shutil.copy2(OUT/'reconcile/replay-noop',f.root/'replay')
        def replay_read():
            return subprocess.run([replay,f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1'],
                                  user=f.runtime,group=f.runtime,extra_groups=[],text=True,capture_output=True,timeout=65)
        recovery = contextlib.nullcontext()
        if mode!=1:
            blocked = replay_read()
            assert (blocked.returncode,blocked.stdout)==(1,'')
            recovery = service(f.root,f.root/'custodian',f.custodian,f.runtime,f.operator)
        with recovery:
            verified = f.verify()
            assert verified[2:5] == (startup_head[6:70],expected_pledge,tip)
            assert history.read_bytes()==startup_history and head.read_bytes()==startup_head and f.rows()==rows
            result = replay_read()
            assert (result.returncode,result.stdout.splitlines())==(0,[f'Journal {state} OutstandingReceipts {outstanding}'])
            if state=='PendingEventMissing':
                assert f.run(state,allow=False)==state and f.verify()==verified and history.read_bytes()==retained
            if rows[0]:
                if state=='PendingConfirmation':
                    assert f.run(state)==state
                assert f.call(2,pledge)[:5]==(0,committed[-32:],cp,b'',4)
                assert f.run('Ready')=='Ready' and history.read_bytes()==base+pending+committed and head.read_bytes()==new_head
            assert f.rows()==rows
            emit(case='append_error',variant=variant,caller=caller,startup_tip=tip,replay=result.stdout.strip(),
                 final_tip=f.verify()[4],suffix_bytes=len(tail),inventory_sha256=inventory)


def storage_fault_reply(kind,mode,publication=False):
    variant = f'publish-err-{mode}' if publication else f'append-{kind}-{mode}'
    with fixture(proof_variant=variant) as (f,genesis,denial):
        event,pledge = event_and_pledge(genesis,denial)
        if kind==2:
            prepared = f.call(1,pledge)
            assert prepared[0]==0 and prepared[1]!=ZERO
            craft(f,denial,event)
        reply = f.call(kind,pledge)
        expected_tip = 4 if publication else kind+1  # Publication follows the durable COMMITTED append.
        assert reply[:5]==(14,ZERO,STORE+LE(1)+LE(0)+genesis,pledge if kind==2 else b'',expected_tip)
        emit(case='publication_fault_reply' if publication else 'append_fault_reply',kind=kind,mode=mode,status=reply[0],receipt=reply[1].hex())


def publication_fault(mode):
    variant = f'publish-err-{mode}'
    with fixture(proof_variant=variant) as (f,genesis,denial):
        history,head = f.root/'data/history',f.root/'data/head'
        base = history.read_bytes()
        prefix = b'WBHD'+struct.pack('<H',1)+STORE+LE(1)+LE(0)+genesis+base[-32:]
        old_head = prefix+sha(b'warband.head.v1\0'+prefix)
        assert head.read_bytes()==old_head and f.verify()[3:5]==(b'',2) and f.rows()==[[],[],[]]
        bundle,calls,caller,inventory = capture_storage_run(f,variant,mode,'publish-error')
        emit(publication_capture=variant,bundle=str(bundle),inventory_sha256=inventory,calls=calls)
        with tempfile.TemporaryDirectory(dir=f.root) as tmp:
            db = shutil.copytree(bundle/'journal',Path(tmp)/'journal')/'active.db'
            with contextlib.closing(sqlite3.connect(db)) as conn:
                conn.execute('BEGIN')
                rows = [list(conn.execute('SELECT * FROM '+t)) for t in ('events','denial_imports','import_watermarks')]
        assert [len(table) for table in rows]==[1,1,1]
        recorded_time, = struct.unpack_from('<Q',rows[0][0][3],40)
        event,pledge = event_and_pledge(genesis,denial,recorded_time)
        ref = STORE,LE(1),LE(1)
        ordinal = denial[11:19]
        assert rows==[[(*ref,event)],[(STORE,ordinal,denial[-32:],*ref[1:])],[(STORE,ordinal)]]
        pending = admin_frame(1,pledge,3,base[-32:])
        committed = admin_frame(2,pledge,4,pending[-32:])
        retained = base+pending+committed
        assert (bundle/'data/history').read_bytes()==retained
        cp = b''.join(ref)+pledge[72:104]
        prefix = b'WBHD'+struct.pack('<H',1)+cp+committed[-32:]
        new_head = prefix+sha(b'warband.head.v1\0'+prefix)
        assert len(prefix)==102 and len(new_head)==134
        published = (bundle/'data/head').read_bytes()
        temporary = bundle/'data/head.tmp'
        if published==new_head and not temporary.exists():
            state = 'new_head'
        elif published==old_head and temporary.exists() and temporary.read_bytes()==prefix:
            state = 'partial_tmp'
        elif published==old_head and temporary.exists() and temporary.read_bytes()==new_head:
            state = 'complete_tmp'
        else:
            raise AssertionError(('unexpected publication files',bundle))
        emit(variant=variant,observed=state)
        assert state==('new_head','partial_tmp','complete_tmp','complete_tmp','new_head')[mode-1]
        full = ['tmp_write 134 134']
        sync_close = ['tmp_sync 0 0','tmp_close 0 0']
        successful_end = sync_close+['head_rename 0 0','directory_sync 0 0']
        expected = [
            ['tmp_write 134 102','tmp_write 32 32']+successful_end,
            ['tmp_write 134 102','tmp_write 32 -1 ENOSPC','tmp_close 0 0'],
            full+['tmp_sync -1 5','tmp_close 0 0'],
            full+sync_close+['head_rename -1 5'],
            full+sync_close+['head_rename 0 0','directory_sync -1 5'],
        ]
        assert calls==expected[mode-1],calls
        replay = shutil.copy2(OUT/'reconcile/replay-noop',f.root/'replay')
        def replay_read():
            return subprocess.run([replay,f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1'],
                                  user=f.runtime,group=f.runtime,extra_groups=[],text=True,capture_output=True,timeout=65)
        recovery = contextlib.nullcontext()
        if mode!=1:
            blocked = replay_read()
            assert (blocked.returncode,blocked.stdout)==(1,'')
            recovery = service(f.root,f.root/'custodian',f.custodian,f.runtime,f.operator)
        with head.open('rb') as visible, recovery:
            verified = f.verify()
            assert verified[2:5]==(cp,b'',4) and f.rows()==rows and history.read_bytes()==retained
            assert head.read_bytes()==new_head and not (f.root/'data/head.tmp').exists()
            assert visible.read()==published
            prior, current = os.fstat(visible.fileno()), head.stat()
            assert prior.st_dev==current.st_dev and (prior.st_ino!=current.st_ino)==(mode!=1)
            assert f.call(2,pledge)[:5]==(0,committed[-32:],cp,b'',4)
            assert f.run('Ready')=='Ready'
            ready = replay_read()
            assert (ready.returncode,ready.stdout.splitlines())==(0,['Journal Ready OutstandingReceipts 0'])
            assert f.verify()==verified and f.rows()==rows and history.read_bytes()==retained and head.read_bytes()==new_head
            emit(case='publication_error',variant=variant,caller=caller,observed=state,before_inode=prior.st_ino,
                 after_inode=current.st_ino,tip=verified[4],replay=ready.stdout.strip())


def existing_event_prefix():
    with fixture() as (f, _, frame):
        vectors = json.loads(VECTORS.read_text())
        pledge = bytes.fromhex(vectors['custody_tuple_hex'])
        event = bytes.fromhex(vectors['task_created']['event_hex'])
        assert f.call(1,pledge)[0] == 0
        f.query('INSERT INTO events VALUES(?,?,?,?)',(STORE,LE(1),LE(1),event))
        before = time.time_ns() // 1000
        f.run('PendingConfirmation')
        after = time.time_ns() // 1000
        stored = f.query('SELECT canonical_event FROM events WHERE sequence=?',(LE(2),))[0][0]
        assert before <= struct.unpack_from('<Q',stored,40)[0] <= after
        assert stored[-64:-32] == sha(frame) and stored[-32:] == pledge[72:104]
        f.run('Ready')
        assert len(f.rows()[0]) == 2


def admin_frame(kind, payload, ordinal, previous):
    header = b'WBCH'+struct.pack('<HBIQ',1,kind,len(payload),ordinal)+previous
    body = header+sha(b'warband.custody.header.v1\0'+header)+payload
    return body+sha(b'warband.custody.record.v1\0'+body)


def interrupted_operator(root, uid, custodian, wire):
    os.setgroups([])
    os.setgid(uid)
    os.setuid(uid)
    assert os.getresuid() == (uid,)*3
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        conn.settimeout(30)
        conn.connect(str(root/'endpoints/operator.sock'))
        assert struct.unpack('3i',conn.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))[1] == custodian
        conn.sendall(wire)
        conn.shutdown(socket.SHUT_WR)
        try:
            assert conn.recv(490) == b'', 'unexpected administrative reply bytes'
        except ConnectionResetError:
            raise SystemExit(42)  # Distinguish reset from an orderly EOF.


def kill_admin(f, wire):
    child = multiprocessing.get_context('fork').Process(target=interrupted_operator,
                      args=(f.root,f.operator,f.custodian,wire))
    fd = os.pidfd_open(f.custodian_pid)
    child.start()
    try:
        deadline = time.monotonic()+25
        while 'State:\tT (stopped)' not in Path(f'/proc/{f.custodian_pid}/status').read_text().splitlines():
            assert child.is_alive() and time.monotonic()<deadline, 'administrative stop was not reached'
            time.sleep(0.01)
        assert child.is_alive()
    finally:
        signal.pidfd_send_signal(fd,signal.SIGKILL)
        os.close(fd)
        child.join(35)
    assert child.exitcode in (0,42), child.exitcode
    return 'EOF' if child.exitcode == 0 else 'reset'


def capture_admin(f, case, wire):
    parent = OUT/'point10-admin'
    parent.mkdir(exist_ok=True)
    bundle = Path(tempfile.mkdtemp(dir=parent,prefix=case+'-'))
    files = [p for dirname in ('data','journal') for p in (f.root/dirname).iterdir()]
    hashes = {}
    for path in files:
        name = str(path.relative_to(f.root))
        dst = bundle/name
        dst.parent.mkdir(exist_ok=True)
        hashes[name] = sha(path.read_bytes()).hex()
        shutil.copyfile(path,dst)
        assert sha(dst.read_bytes()).hex() == hashes[name]
    meta = dict(case=case,wbcr=wire.hex(),operator_uid=f.operator,kernel=os.uname().release,
                host=os.uname().nodename,files=sorted(hashes),source=subprocess.check_output(
                ['git','-c',f'safe.directory={Path.cwd()}','rev-parse','HEAD'],text=True).strip())
    inventory = seal_capture(bundle,hashes,meta)
    emit(admin_capture=case,bundle=str(bundle),inventory_sha256=inventory)
    return bundle


def admin_kill(edge):
    genesis = edge <= 3
    with fixture(proof_variant=f'admin-{edge}', fresh=genesis) as (f, _, _):
        history, head = f.root/'data/history', f.root/'data/head'
        if genesis:
            op, payload, tip, old_history = 4, ENROLL, 0, b''
            checkpoint = STORE+LE(1)+LE(0)+sha(b'warband.genesis.v1\0'+ENROLL)
        else:
            f.run('Ready')
            old_rows, old_cp = f.rows(), f.verify()[2]
            assert [len(r) for r in old_rows]==[1,1,1] and old_cp[:32]==STORE+LE(1)+LE(1)
            old_db = f.db.read_bytes()
            old_head = head.read_bytes()
            body = bytearray(bytes.fromhex(json.loads(VECTORS.read_text())['task_created']['event_hex'])[:-32])
            body[32:40] = LE(2)
            digest = sha(b'warband.event.v1\0'+body)
            link = sha(b'warband.link.v1\0'+STORE+LE(1)+LE(2)+old_cp[32:]+digest)
            pledge = old_cp+LE(2)+link+digest
            response = f.call(1,pledge)
            assert response[0]==0
            pending_hash = response[1]
            old_history = history.read_bytes()
            prior = f.verify()
            assert prior[2:5]==(old_cp,pledge,5) and old_history[-32:]==pending_hash
            auth_reason = bytes([91])*16+struct.pack('<H',6)+b'review'
            def epoch_payload(binding):
                next_head = sha(b'warband.epoch.v1\0'+old_cp+LE(2)+auth_reason+binding)
                return old_cp+LE(2)+LE(0)+next_head+auth_reason+binding
            op, payload, tip = 5, epoch_payload(pending_hash), prior[4]
            checkpoint = STORE+LE(2)+LE(0)+payload[80:112]
        wire = b'WBCR'+struct.pack('<HBI',1,op,len(payload))+payload
        frame = admin_frame(op-1,payload+LE(f.operator),tip+1,old_history[-32:] or ZERO)
        prefix = b'WBHD'+struct.pack('<H',1)+checkpoint+frame[-32:]
        new_head = prefix+sha(b'warband.head.v1\0'+prefix)
        caller = kill_admin(f,wire)
        bundle = capture_admin(f,f'edge-{edge}',wire)
        length = {1:0,2:83,3:len(frame),4:83,5:len(frame)}[edge]
        assert (bundle/'data/history').read_bytes()==old_history+frame[:length]
        assert not (bundle/'data/head.tmp').exists() and not (bundle/'journal/epoch2.db').exists()
        if genesis:
            assert not head.exists() and not list((f.root/'journal').iterdir())
        else:
            assert head.read_bytes()==(new_head if edge==5 else old_head) and f.db.read_bytes()==old_db
        with service(f.root,f.root/'custodian',f.custodian,f.runtime,f.operator):
            if edge in (1,2):
                assert not history.read_bytes() and not head.exists()
                assert f.call(3,STORE+LE(0)+LE(0))[0]==11
            elif edge==4:
                assert f.verify()==prior and history.read_bytes()==old_history and head.read_bytes()==old_head
                assert f.call(1,pledge)[1]==pending_hash
            else:
                f.epoch = 1 if genesis else 2
                assert f.verify()[2:5]==(checkpoint,b'',tip+1)
                assert head.read_bytes()==new_head and history.read_bytes()==old_history+frame
            if edge!=4:
                assert f.call(op,payload)[:5]==(0,frame[-32:],checkpoint,b'',tip+1)
                assert history.read_bytes()==old_history+frame and head.read_bytes()==new_head
            if not genesis:
                archive = f.db
                replay = shutil.copy2(OUT/'reconcile/replay-noop',f.root/'replay')
                if edge==5:
                    f.db = f.root/'journal/epoch2.db'
                    f.archives = [archive,wire.hex()]
                    f.run('LockUnavailable',allow=False)
                    assert not f.db.exists()
                    f.provision()
                    f.archives = []
                    f.run('EpochMismatch',allow=False)
                    assert archive.read_bytes()==old_db
                    f.archives = [archive,(wire[:11]+epoch_payload(ZERO)).hex()]
                    f.run('IntegrityFault',allow=False)
                    assert archive.read_bytes()==old_db and f.rows()==[[],[],[]]
                    f.archives = [archive,wire.hex()]
                    f.run('Ready')
                    assert f.rows()==[[],[],[]] and f.verify()[2:5]==(checkpoint,b'',tip+1)
                else:
                    f.run('PendingEventMissing',allow=False)
                cmd = [replay,f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),str(f.epoch),*f.archives]
                result = subprocess.run(cmd,user=f.runtime,group=f.runtime,extra_groups=[],capture_output=True,text=True,timeout=65)
                state = 'Ready' if edge==5 else 'PendingEventMissing'
                assert (result.returncode,result.stdout.splitlines())==(0,[f'Journal {state} OutstandingReceipts 0'])
                assert archive.read_bytes()==old_db
        emit(case='admin_kill',edge=edge,caller=caller,custodian_pid=f.custodian_pid,reply_bytes=0,retained_length=length,epoch=f.epoch,tip=tip if edge==4 else tip+1)


def established_metadata_loss():
    with fixture() as (f, _, _):
        f.run('Ready')
        old_rows, database = f.rows(), f.db.read_bytes()
        assert len(old_rows[0])==1
        fd = os.pidfd_open(f.custodian_pid)
        try:
            poller = select.poll()
            poller.register(fd,select.POLLIN)
            signal.pidfd_send_signal(fd,signal.SIGKILL)
            assert poller.poll(5000), 'custodian did not exit'
        finally:
            os.close(fd)
        for name in ('head','history'):
            (f.root/'data'/name).rename(f.root/('saved-'+name))
        journal = f.root/'journal'
        os.chown(journal,f.operator,f.operator)
        journal.chmod(0o555)
        wire = b'WBCR'+struct.pack('<HBI',1,4,len(ENROLL))+ENROLL
        capture_admin(f,'established-missing',wire)
        with service(f.root,f.root/'custodian',f.custodian,f.runtime,f.operator):
            assert f.call(3,STORE+LE(0)+LE(0))[0]==11
            refusal = f.call(4,ENROLL)
            assert refusal[0]==16 and refusal[4]==1
            denial = (f.root/'data/history').read_bytes()
            body = denial[83:-32]
            assert body[:26]==STORE+LE(0)+struct.pack('<H',16) and body[64:72]==LE(f.operator)
            assert body[31:63]==sha(b'warband.custody.denial.v1\0'+struct.pack('<IB',len(wire),1)+wire)
            assert denial==admin_frame(5,body,1,ZERO) and denial[-32:]==refusal[1]
            assert not (f.root/'data/head').exists() and f.rows()==old_rows and f.db.read_bytes()==database
        emit(case='established_metadata_loss',verify='CheckpointMissing',enroll='CheckpointConflict',rejections=1)


def retained_segments():
    with fixture() as (f, _, frame):
        with f.db.open('rb') as held:
            fcntl.flock(held,fcntl.LOCK_EX)
            f.run('LockUnavailable',allow=False)
        f.run('Ready')
        rows = f.rows()
        assert [len(r) for r in rows] == [1,1,1] and rows[2][0] == (STORE,LE(1))
        assert rows[0][0][3][-64:-32] == sha(frame)
        old = f.verify()[2]
        reason = struct.pack('<H',6)+b'review'
        auth = bytes([91])*16
        head = sha(b'warband.epoch.v1\0'+old+LE(2)+auth+reason+ZERO)
        payload = old+LE(2)+LE(0)+head+auth+reason+ZERO
        assert f.call(5,payload)[0] == 0
        request_hex = (b'WBCR'+struct.pack('<HBI',1,5,len(payload))+payload).hex()
        archive = f.db
        f.db = f.root/'journal'/'epoch2.db'
        f.epoch = 2
        f.provision()
        denied(f.call(4,ENROLL,denied_admin=True))
        f.run('EpochMismatch',allow=False)
        # A valid but substituted handoff does not chain to the authenticated head.
        other = old+LE(2)+LE(0)+sha(b'warband.epoch.v1\0'+old+LE(2)+auth+reason+bytes([7])*32)+auth+reason+bytes([7])*32
        f.archives = [archive,(b'WBCR'+struct.pack('<HBI',1,5,len(other))+other).hex()]
        f.run('IntegrityFault',allow=False)
        assert f.rows() == [[],[],[]]
        f.archives = [archive,request_hex]
        f.run('Ready')
        result = f.rows()
        assert [len(r) for r in result] == [1,1,1] and result[1][0][1] != LE(1)
        custody = f.verify()
        replay = f.run('ConfirmedResponsePending',(1,frame[-32:]))
        assert replay.split()[1:] == [STORE.hex(),'1','1']
        assert f.rows() == result and f.verify() == custody
        # The client sent zero bytes. The real custodian still audits the empty connection.
        f.run('CustodyUnavailable',allow=False,uid=f.operator)
        denied_reply = f.verify(custody[4])
        empty_frame = denied_reply[5]
        assert denied_reply[2:4] == custody[2:4] and denied_reply[4] == custody[4]+1
        assert int.from_bytes(empty_frame[109:113],'little') == 0 and f.rows() == result
        with contextlib.closing(sqlite3.connect(archive)) as conn:
            assert list(conn.execute('SELECT * FROM events')) == rows[0]
            conn.execute('DELETE FROM events')
            conn.commit()
        f.run('IntegrityFault',allow=False)
        assert f.rows() == result


if __name__ == '__main__':
    assert os.getuid()==0 and limits('self')==(256*1024*1024,0)
    for case in ('PendingConfirmation','ConfirmedResponsePending','PendingEventMissing','UnattestedTail','IntegrityFault'):
        restart(case)
    import_process_kill('after-commit')
    import_process_kill('before-ack')
    for edge in (1, 2, 3, 4):
        confirm_kill('publish', edge)
        confirm_kill('committed', edge)
    for prefix_length in (None, 0, 83):
        prepare_kill(prefix_length)
    for stop in ('after-prepare', 'event-insert', 'wal-commit'):
        receipt_transaction_kill(stop)
    existing_event_prefix()
    retained_segments()
    for edge in range(1,6):
        admin_kill(edge)
    established_metadata_loss()
    for kind in (1,2):
        for mode in (1,2,3):
            append_fault(kind,mode)
            if mode!=1:
                storage_fault_reply(kind,mode)
    for mode in range(1,6):
        publication_fault(mode)
        if mode!=1:
            storage_fault_reply(2,mode,publication=True)
    emit(result='pass')
