"""Real-UID reconciliation and post-COMMIT process recovery. Run in the same disposable scope as the denial harness."""
import contextlib
import fcntl
import json
import os
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
def fixture(*, measure=False, proof_variant=None):
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
        first_service = root/'custodian'
        if proof_variant is not None:
            first_service = shutil.copy2(OUT/'custodian'/proof_variant/'custodian', root/'proof-custodian')
        with service(root,first_service,*users,stderr_path=log) as f.custodian_pid:
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


def kill_importer(f, stop):
    binary = shutil.copy2(OUT/'reconcile'/f'reconcile-custody-stop-{stop}', f.root/'fault-importer')
    args = [binary, f.db, f.root/'endpoints/runtime.sock', str(f.custodian), STORE.hex(), '1', '0', '-']
    with subprocess.Popen(args, user=f.runtime, group=f.runtime, extra_groups=[], stdout=subprocess.PIPE) as child:
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


def publication_kill(edge):
    with fixture(proof_variant=f'publish-{edge}') as (f, genesis, frame):
        head = f.root/'data/head'
        temporary = f.root/'data/head.tmp'
        history = f.root/'data/history'
        old_head, old_history = head.read_bytes(), history.read_bytes()
        assert f.verify()[4] == 2 and f.rows() == [[], [], []]
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
        assert history.read_bytes() == retained
        receipt = retained[-32:]
        checkpoint = b''.join(ref) + pledge[72:104]
        prefix = b'WBHD' + struct.pack('<H', 1) + checkpoint + receipt
        new_head = prefix + sha(b'warband.head.v1\0' + prefix)
        assert old_head != new_head
        assert head.read_bytes() == (old_head if edge <= 2 else new_head)
        if edge <= 2:
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
            assert verified[2:5] == (checkpoint, b'', 4)
            assert head.read_bytes() == new_head and not temporary.exists()
            exact = f.call(2, pledge)
            assert exact[:5] == (0, receipt, checkpoint, b'', 4)
            ready = run_replay()
            assert (ready.returncode, ready.stdout.splitlines()) == (0, ['Journal Ready OutstandingReceipts 0'])
            assert history.read_bytes() == retained and f.verify() == verified and f.rows() == rows
            emit(case='publication_kill', edge=edge, custodian_pid=f.custodian_pid, caller=output.strip(),
                 published_before='old' if edge <= 2 else 'new', temp_before=edge <= 2,
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
        publication_kill(edge)
    for prefix_length in (None, 0, 83):
        prepare_kill(prefix_length)
    existing_event_prefix()
    retained_segments()
    emit(result='pass')
