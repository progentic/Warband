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
def fixture(*, measure=False):
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
        with service(root,root/'custodian',*users,stderr_path=log):
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


def post_commit_process_kill():
    with fixture() as (f, genesis, frame):
        before = f.verify()
        assert f.rows() == [[], [], []] and not before[3]
        binary = shutil.copy2(OUT/'reconcile/reconcile-custody-stop-after-commit', f.root/'fault-importer')
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
                    raise AssertionError(f'importer {child.pid} did not reach its post-COMMIT stop')
            finally:
                child.kill()
                status = child.wait(timeout=10)
            assert status == -signal.SIGKILL and child.stdout.read() == b''

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

        def check_replay(stage, custody, expected_tip, expected_journal, expected_outstanding):
            result = subprocess.run([replay, f.db, f.root/'endpoints/runtime.sock', str(f.custodian),
                                     STORE.hex(), str(f.epoch)], user=f.runtime, group=f.runtime,
                                    extra_groups=[], capture_output=True, text=True, timeout=65)
            # The only event is audit-only. Exact stdout also requires zero task rows.
            journal = f'Journal {expected_journal} OutstandingReceipts {expected_outstanding}'
            assert result.returncode == 0 and result.stdout.splitlines() == [journal], (result.stdout, result.stderr)
            assert custody[4] == expected_tip and f.verify() == custody and f.rows() == rows
            emit(case='post_commit_replay', stage=stage, tip=custody[4], output=result.stdout.strip())

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
        emit(case='post_commit_process_kill', pid=child.pid, stopped='SIGSTOP', reaped=status,
             pending_tip=tip, confirmed_tip=confirmed[4], second_tip=second[4],
             receipt_hash=frame[-32:].hex(), watermark=int.from_bytes(ordinal, 'little'))


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
    post_commit_process_kill()
    existing_event_prefix()
    retained_segments()
    emit(result='pass')
