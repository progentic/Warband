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
import tempfile
from pathlib import Path

from test_custody_denial import STORE, VECTORS, emit, limits, sha
from test_receipt_import import OUT, LE, fixture, capture_files, inspect_wal, seal_capture


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


def expected_task(task, run, versions, complete, auth, consumed, revoked, attempt, obs, verdict, disposition=0, reason=0):
    bit = lambda value: str(bool(value)).lower()
    return ' '.join(map(str,[STORE.hex(),1,task.hex(),run.hex(),*versions,bit(complete),auth,
                             bit(consumed),bit(revoked),attempt.hex(),obs,verdict,disposition,reason]))


def replay_fixture(f, expected_rows, *, live=False, failure=None, journal='Ready'):
    before = f.rows(),f.verify()
    binaries = ('replay-noop','replay-noop-proof','replay-noop-proof') if journal=='Ready' else ('replay-noop',)
    for name in binaries:
        binary = f.root/name
        if not binary.exists():
            shutil.copy2(OUT/'reconcile'/name,binary)
        args = [binary,f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1']
        p = subprocess.run(args,user=f.runtime,group=f.runtime,extra_groups=[],capture_output=True,text=True,timeout=65)
        lines = p.stdout.splitlines()
        if failure:
            assert p.returncode==1 and lines==['Failure '+failure+' IntegrityFault'],(lines,p.stderr)
        else:
            assert p.returncode==0 and lines[0]==f'Journal {journal} OutstandingReceipts 0',(lines,p.stderr)
            assert [v[5:] for v in lines if v.startswith('Task ')]==expected_rows,lines
            assert [v[5:] for v in lines if v.startswith('Live ')]==(expected_rows if live and name.endswith('-proof') else []),lines
        assert (f.rows(),f.verify())==before
    emit(replay=failure or journal,oracle=expected_rows,live_comparison=live,tip=before[1][4])


def mixed_replay(f, genesis, accepted):
    chain = confirmed_events(f,genesis)
    def record(kind, producer, payload):
        seq = len(chain)+1
        ref = STORE+LE(1)+LE(seq)
        body = b'WBEV'+struct.pack('<HH',1,kind)+ref+struct.pack('<QHHI',0,producer,1,len(payload))+payload
        prev = linked_head(chain[-1])
        wire = body+prev
        pledge = STORE+LE(1)+LE(seq-1)+prev+LE(seq)+linked_head(wire)+sha(b'warband.event.v1\0'+body)
        assert f.call(1,pledge)[0]==0
        f.query('INSERT INTO events VALUES(?,?,?,?)',(STORE,LE(1),LE(seq),wire))
        assert f.call(2,pledge)[0]==0
        chain.append(wire)
        return ref

    names = [bytes([i])*16 for i in range(16,48)]
    tasks = [(names[i],names[i+1]) for i in (0,10,20)]
    for i,(task,run) in enumerate(tasks):
        ids = task+run+names[10*i+2]
        record(1,1,ids+sha(b'warband.task.v1\0'+ids)+names[10*i+3])
    oracle = [accepted]
    for i,(task,run) in enumerate(tasks):
        group = names[10*i:]
        prop = task+run+group[4]+LE(1)+LE(1)+struct.pack('<HB I HBB',1,0,0,1,1,0)
        prop_ref = record(2,1,prop)
        permit = i!=0
        cap = group[5] if permit else bytes(16)
        auth = record(3,2,prop_ref+LE(0)+bytes([1 if permit else 2])+cap+LE(int(permit))+bytes([permit])+group[6])
        if i==0:
            oracle.append(expected_task(task,run,(1,0),False,2,False,False,bytes(16),0,0))
        elif i==1:
            revocation = record(9,2,auth+cap+LE(1)+struct.pack('<H',12))
            oracle.append(expected_task(task,run,(1,2),False,1,False,True,bytes(16),0,0))
        else:
            attempt = group[7]
            claim = record(4,2,auth+attempt+cap+LE(1)+LE(1)+sha(b'warband.proposal.v1\0'+prop)+LE(0))
            obs = record(5,3,claim+group[8]+bytes.fromhex('02010000000000'))
            record(6,4,obs+claim+sha(b'warband.event.v1\0'+chain[-1][:-32])+bytes.fromhex('010002')+group[9])
            record(10,5,claim+LE(2)+struct.pack('<BH',1,10))
            oracle.append(expected_task(task,run,(1,3),False,1,True,False,attempt,2,2,1,10))
    replay_fixture(f,oracle)
    # Four different SQLite edits retain the same authenticated custody head.
    seq = len(chain)
    def set_event(n,wire):
        f.query('UPDATE events SET canonical_event=? WHERE sequence=?',(wire,LE(n)))
    changed = bytearray(chain[-1]); changed[40] ^= 1
    set_event(seq,changed)
    replay_fixture(f,[],failure='IntegrityFault')
    f.query('DELETE FROM events WHERE sequence=?',(LE(seq),))
    replay_fixture(f,[],failure='IntegrityFault')
    f.query('INSERT INTO events VALUES(?,?,?,?)',(STORE,LE(1),LE(seq),chain[-2]))
    set_event(seq-1,chain[-1])
    replay_fixture(f,[],failure='IntegrityFault')
    set_event(seq-1,chain[-2])
    replacement = bytearray(chain[-1]); replacement[96]=2  # valid RejectStop instead of Indeterminate
    set_event(seq,replacement)
    replay_fixture(f,[],failure='IntegrityFault')
    set_event(seq,chain[-1])
    # The custodian confirms an observation whose claim Ref resolves to a revocation.
    record(5,3,revocation+names[-1]+bytes.fromhex('02010000000000'))
    assert confirmed_events(f,genesis)==chain
    replay_fixture(f,[],failure='InvalidReference')

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

        events = confirmed_events(f,genesis)
        task,run = events[0][56:72],events[0][72:88]
        if kill_at is None:
            want = expected_task(task,run,(2,3),True,1,True,False,events[4][88:104],1,1)
        elif kill_at=='observation':
            want = expected_task(task,run,(1,3),False,1,True,True,events[4][88:104],1,1)
        else:
            want = expected_task(task,run,(1,2),False,1,True,False,events[4][88:104],2,2)
        replay_fixture(f,[want],live=True)
        if kill_at is None: mixed_replay(f,genesis,want)


def classify_live_snapshot(db, genesis, custody, receipt, accepting):
    # A single SQLite snapshot must reproduce the custody-confirmed prefix before its tail is inspected.
    _, _, cp, pledge, tip, captured_receipt = custody
    assert captured_receipt == receipt
    seq = int.from_bytes(cp[24:32], 'little')
    rows = list(db.execute('SELECT * FROM events ORDER BY sequence'))  # fixture sequences 1..8
    events = [row[3] for row in rows]
    head = genesis
    for n, row in enumerate(rows[:seq], 1):
        assert row[:3] == (STORE, LE(1), LE(n)) and row[3][8:40] == b''.join(row[:3])
        assert row[3][-32:] == head
        head = linked_head(row[3])
    assert cp == STORE+LE(1)+LE(seq)+head and len(rows) >= seq
    prefix = events[:seq]
    assert [ev[6] for ev in prefix] == ([1,2,8,3,4,5,6] if accepting else [1,2,8,3,4])
    assert prefix[2][60:92] == sha(receipt)
    imports = [(STORE, receipt[11:19], receipt[-32:], LE(1), LE(3))]
    assert list(db.execute('SELECT * FROM denial_imports')) == imports
    assert list(db.execute('SELECT * FROM import_watermarks')) == [(STORE, receipt[11:19])]
    ref = STORE+LE(1)+LE(seq+1)
    assert pledge[:72] == cp+LE(seq+1)
    assert pledge[72:104] == sha(b'warband.link.v1\0'+ref+head+pledge[104:])
    attempt = prefix[4][88:104]
    bindings = list(db.execute('SELECT * FROM accepted_attempts')) if accepting else []
    if len(events) == seq and not bindings:
        return 'PendingEventMissing', events, bindings
    if len(events) != seq+1:
        return 'IntegrityFault', events, bindings
    wire = events[-1]
    if (rows[-1][:3] != (STORE,LE(1),LE(seq+1)) or wire[8:40] != ref or wire[-32:] != head
            or linked_head(wire) != pledge[72:104] or sha(b'warband.event.v1\0'+wire[:-32]) != pledge[104:]):
        return 'IntegrityFault', events, bindings
    if accepting:
        tid = wire[120:136]
        expected = [(STORE,LE(1),attempt,tid,LE(seq+1))]
        if (bindings != expected or wire[6:8] != LE(7)[:2] or wire[56:120] != prefix[-1][8:40]+prefix[4][8:40]
                or wire[136:161] != LE(1)+LE(2)+LE(2)+b'\x02'):
            return 'IntegrityFault', events, bindings
        for key, value in [('attempt_id',attempt), ('transition_id',tid), ('sequence',LE(seq+1))]:
            found = db.execute('SELECT * FROM accepted_attempts WHERE store_id=? AND epoch=? AND '+key+'=?',
                               (STORE,LE(1),value)).fetchall()
            assert found == expected, (key,found)
    elif wire[6:8] != LE(5)[:2] or wire[56:88] != prefix[4][8:40] or wire[104:111] != b'\x01\x01\0NOOP':
        return 'IntegrityFault', events, bindings
    return 'PendingConfirmation', events, bindings


def live_transaction_kill(accepting, stage):
    actor = 'accept-noop' if accepting else 'noop-gate'
    with fixture() as (f, genesis, receipt):
        seed(f)
        common = [f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1']
        user = dict(user=f.runtime,group=f.runtime,extra_groups=[],text=True)
        def binary(name):
            return shutil.copy2(OUT/'reconcile'/name, f.root/name)
        def run(cmd, expected, rc):
            p = subprocess.run(cmd,**user,capture_output=True,timeout=65)
            assert p.returncode == rc and p.stdout.splitlines()[-1] == expected,(p.stdout,p.stderr)
            return p.stdout.splitlines().count('primitive_invoked')

        gate = [binary('noop-gate-witness'), *common, '2']
        invocations = 0
        if accepting:
            invocations = run(gate,'gate_result Dispatched',0)
            events = confirmed_events(f,genesis)
            check_evidence(events,events[:5],True)
            accept = binary('accept-noop')
            assert run([accept,*common,'provision-index'],'IndexVerified',0) == 0
            args = [*common,str(len(events)),'1','2']
            fresh = [accept,*args]
        else:
            args, fresh = gate[1:], gate
        proof = binary(actor+'-'+stage)
        with subprocess.Popen([proof,*args],**user,stdout=subprocess.PIPE,stderr=subprocess.PIPE) as child:
            try:
                wait_for_stop(child)
            finally:
                child.kill()
                output, err = child.communicate(timeout=65)
            assert child.returncode == -signal.SIGKILL
        parent = OUT/'point9-transactions'
        parent.mkdir(exist_ok=True)
        bundle = Path(tempfile.mkdtemp(dir=parent,prefix=actor+'-'+stage+'-'))
        hashes, owners, sidecars = capture_files(f,bundle)
        invocations += output.splitlines().count('primitive_invoked')
        assert invocations == 1
        assert not any(s.startswith(('gate_result','Accepted','Recorded')) for s in output.splitlines())
        wal = inspect_wal(bundle/'journal/active.db-wal')
        witness = dict(line.split() for line in err.splitlines())
        custody = f.verify()
        meta = dict(actor=actor,stage=stage,wal=wal,hook=witness,sidecars=sidecars,file_uid_gid_mode=owners,
                    tip=custody[4],kernel=os.uname().release,host=os.uname().nodename,pledge=custody[3].hex(),
                    source=subprocess.check_output(['git','-c',f'safe.directory={Path.cwd()}','rev-parse','HEAD'],text=True).strip())
        inventory = seal_capture(bundle,hashes,meta)
        emit(point9_capture=str(bundle),actor=actor,stage=stage,inventory_sha256=inventory)
        with tempfile.TemporaryDirectory(dir=f.root) as tmp:
            journal = shutil.copytree(bundle/'journal',Path(tmp)/'journal')
            with contextlib.closing(sqlite3.connect(journal/'active.db')) as db:
                db.execute('BEGIN')
                outcome, events, bindings = classify_live_snapshot(db,genesis,custody,receipt,accepting)
        emit(actor=actor,stage=stage,observed=outcome,events=len(events),bindings=len(bindings),wal=wal)
        assert outcome == ('PendingConfirmation' if stage=='commit' else 'PendingEventMissing')
        if stage=='commit':
            assert 0 < wal['last_commit'] == wal['valid_frames'] == int(witness['wal_frames']) < int(witness['wal_threshold'])
        else:
            assert not witness
        task, run_id, attempt = events[0][56:72],events[0][72:88],events[4][88:104]
        def projection(complete, observed):
            return expected_task(task,run_id,(2,3) if complete else (1,2),complete,1,True,False,attempt,observed,observed)
        before = projection(False,int(accepting))
        replay_fixture(f,[before],journal=outcome)
        def snapshot():
            binding_rows = f.query('SELECT * FROM accepted_attempts') if accepting else []
            return f.rows(),binding_rows,f.verify()
        original = snapshot()
        if outcome=='PendingEventMissing':
            refusal = 'ReconciliationRequired' if accepting else 'gate_result ReconciliationRequired'
            for _ in range(2):
                assert run(fresh,refusal,1) == 0 and snapshot() == original
            replay_fixture(f,[before],journal=outcome)
        else:
            if accepting:
                result = ' '.join(['Recorded',STORE.hex(),'1',str(len(events)),events[-1][120:136].hex(),'2','3'])
            else:
                result = 'gate_result EvaluationVerified'
            assert run(fresh,result,0) == 0
            final = confirmed_events(f,genesis)
            if accepting:
                assert final == events and snapshot()[:2] == original[:2]
            else:
                assert final[:-1] == events
                check_evidence(final,events[:5],True)
            settled = snapshot()
            assert settled[-1][4] == custody[4]+(1 if accepting else 3)
            assert run(fresh,result,0) == 0 and snapshot() == settled
            replay_fixture(f,[projection(accepting,1)],live=True)
        emit(case='live_transaction_kill',actor=actor,stage=stage,observed=outcome,initial_tip=custody[4],
             final_tip=f.verify()[4],total_invocations=invocations,bundle=str(bundle),inventory_sha256=inventory)


if __name__ == '__main__':
    assert os.getuid() == 0 and limits('self') == (256*1024*1024,0)
    for boundary in (None,'claim','return','observation'):
        exercise(boundary)
    for accepting in (False, True):
        for stage in ('insert', 'commit'):
            live_transaction_kill(accepting, stage)
    emit(result='pass')
