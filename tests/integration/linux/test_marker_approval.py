"""Drive the deployed CLI under distinct kernel UIDs. Only malformed or disconnected peers use raw packets."""
import contextlib
import fcntl
import os
import select
import signal
import shutil
import socket
import struct
import subprocess
import time

from test_receipt_import import ENROLL, LE, OUT, STORE, as_user, denied, emit, fixture, sha

PAYLOAD = b'Warband review\n'


def identity(root, uid):
    return dict(cwd=root, user=uid, group=uid, extra_groups=[])


def line(proc):
    assert select.select([proc.stdout], [], [], 15)[0], 'CLI timed out'
    value = proc.stdout.readline()
    assert value, (proc.poll(), proc.stderr.read() if proc.poll() is not None else '')
    return value.decode().rstrip()


@contextlib.contextmanager
def server(f, mode, projection=None):
    p = subprocess.Popen(['./review',mode], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, bufsize=0, **identity(f.root,f.runtime))
    try:
        if mode=='serve':
            p.stdin.write(PAYLOAD)
        p.stdin.close()
        if mode=='receipts':
            assert line(p)==f'ConfirmedProjection 1 {projection}'
        assert line(p)=='AwaitingOperator'
        yield p
    finally:
        if p.poll() is None:
            p.kill()
        p.wait(timeout=5)


def cli(f, proposal, answer, before_decision=None):
    with subprocess.Popen(['./review','decide'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, bufsize=0, **identity(f.root,f.operator)) as p:
        try:
            display = [line(p) for _ in range(6)]
            _, fp, _, digest = binding(proposal)
            assert display[0]==f'Proposal {STORE.hex()} 1 3'
            assert display[1]=='Task {} Run {} ProposalID {} Attempt {}'.format(
                *(proposal[i:i+16].hex() for i in (56,72,88,104)))
            device,inode = struct.unpack_from('<QQ',proposal,136)
            assert display[2]==f'Create marker in private directory {proposal[120:136].hex()} device {device} inode {inode}'
            assert display[3].startswith('Versions 1 0 policy 2')
            assert display[4]==f'Fingerprint {fp.hex()} Length {len(PAYLOAD)} SHA256 {digest.hex()}'
            assert display[5]=='Type approve or reject and press Enter.'
            if before_decision:
                before_decision()
            p.stdin.write(answer+b'\n')
            p.stdin.close()
            result=line(p)
            rc=p.wait(timeout=10)
            return rc,result
        finally:
            if p.poll() is None:
                p.kill()


def binding(wire):
    ref = wire[8:40]
    return ref,sha(b'warband.marker.proposal.v1\0'+ref+wire[56:-32]),wire[183:187],sha(wire[187:-32])


def wire_peer(f,case,proposal):
    root=f.root.stat()
    with socket.socket(socket.AF_UNIX,socket.SOCK_SEQPACKET) as s:
        s.settimeout(10)
        s.connect(f'\0warband.approval.{root.st_dev}.{root.st_ino}')
        received=s.recv(8192)
        if case=='unauthorized':
            assert not received
            return b''
        assert received==proposal
        packet=bytearray(b''.join(binding(received))+b'\x01')
        if case in ('ref','fingerprint','length','digest'):
            packet[{'ref':24,'fingerprint':32,'length':64,'digest':68}[case]]^=1
        s.sendall(packet)
        if case in ('lost_reply','commit12','commit13'):
            return b''
        reply=s.recv(100)
        assert len(reply)==33 and reply[1:]==bytes(32)
        return reply


def approval_case(case):
    with fixture() as (f,genesis,_):
        (f.root/'intake.anchor').write_bytes(STORE+LE(1)+LE(0)+genesis+struct.pack('<I',f.custodian))
        (f.root/'approval.ids').write_bytes(struct.pack('<II',f.runtime,f.operator))
        parent=f.root/'attempts'
        parent.mkdir(mode=0o700)
        os.chown(parent,f.runtime,f.runtime)
        shutil.copy2(OUT/'reconcile/marker-approval',f.root/'review')
        def snapshot():
            return f.verify(),f.rows(),(f.root/'data/history').read_bytes(),(f.root/'data/head').read_bytes()
        edge = {'commit12':12,'commit13':13}.get(case)
        if edge:
            shutil.copy2(OUT/'reconcile'/f'marker-approval-{edge}',f.root/'review')
        with server(f,'serve') as srv:
            base=snapshot()
            assert base[0][4]==8
            wire=f.query('SELECT canonical_event FROM events WHERE sequence=?',(LE(3),))[0][0]
            directory,=parent.iterdir()
            def between():
                # A distinct writer can actually take the gate while the CLI has the display.
                with open(f.db,'rb') as gate:
                    fcntl.flock(gate,fcntl.LOCK_EX|fcntl.LOCK_NB)
                if case=='role_change':
                    (f.root/'approval.ids').write_bytes(struct.pack('<II',f.runtime,f.operator+1))
                if case=='directory':
                    directory.rename(f.root/'held-original')
                    directory.mkdir(mode=0o700)
                    os.chown(directory,f.runtime,f.runtime)
                if case=='stale':
                    # A real custody refusal changes receipt coverage after the display.
                    denied(f.call(4,ENROLL,denied_admin=True))
            if case=='unauthorized':
                as_user(f.custodian,lambda: wire_peer(f,case,wire))
                assert srv.poll() is None and snapshot()==base
                assert cli(f,wire,b'reject')==(0,f'Rejected {STORE.hex()} 1 4')
                expected='Rejected'
            elif case in ('approve','reject','directory','role_change','stale'):
                answer=b'reject' if case=='reject' else b'approve'
                rc,result=cli(f,wire,answer,between)
                expected={'approve':'Permitted','reject':'Rejected','directory':'DirectoryHold','role_change':'Withheld','stale':'ReconciliationRequired'}[case]
                suffix=f' {STORE.hex()} 1 4' if case in ('approve','reject') else ''
                assert (rc,result)==(0 if suffix else 1,expected+suffix),(rc,result)
            else:
                as_user(f.operator,lambda: wire_peer(f,case,wire))
                if edge:
                    until=time.monotonic()+10
                    while time.monotonic()<until:
                        ev=os.waitid(os.P_PID,srv.pid,os.WSTOPPED|os.WEXITED|os.WNOHANG|os.WNOWAIT)
                        if ev:
                            assert ev.si_code==os.CLD_STOPPED and ev.si_status==signal.SIGSTOP
                            break
                        time.sleep(.01)
                    else: raise TimeoutError('post-COMMIT stop')
                    srv.kill()
                    assert srv.wait(timeout=5)==-signal.SIGKILL
                    captured=snapshot()
                    assert captured[0][4]==(9 if edge==12 else 11) and captured[0][3]
                    shutil.copy2(OUT/'reconcile/marker-approval',f.root/'review')
                    for attempt,(answer,outcome) in enumerate(((b'reject','DecisionConflict'),(b'approve','Recorded'),(b'approve','Recorded'))):
                        with server(f,'receipts',int(edge==13 and attempt==2)) as receipt_server:
                            rc,result=cli(f,wire,answer)
                            assert (rc,result)==((0,f'Recorded {STORE.hex()} 1 4') if answer==b'approve' else (1,outcome))
                            assert line(receipt_server)==outcome+' LiveGrant false'
                            assert receipt_server.wait(timeout=5)==rc
                        if answer==b'reject':
                            assert snapshot()==captured
                        else:
                            state=snapshot()
                            assert state[0][4]==captured[0][4]+1 and not state[0][3] and state[1]==captured[1]
                    assert not list(directory.iterdir())
                    emit(marker_approval=case,confirmed_tip=state[0][4],fresh_grant=False)
                    return
                expected={'lost_reply':'Permitted'}.get(case,'BindingMismatch')
            live=expected=='Permitted'
            assert line(srv)==f'{expected} LiveGrant {str(live).lower()}'
            assert srv.wait(timeout=10)==(0 if expected in ('Permitted','Rejected') else 1)
        settled=snapshot()
        assert directory.is_dir() and not list(directory.iterdir())
        if expected not in ('Permitted','Rejected'):
            if case=='stale':
                assert settled[0][2:4]==base[0][2:4] and settled[0][4]==9 and settled[1]==base[1]
            else:
                assert settled==base
            with server(f,'receipts',0):
                assert snapshot()==settled
            emit(marker_approval=case,result=expected,projection=[1,0],permit=False)
            return
        records=sorted(settled[1][0],key=lambda row:int.from_bytes(row[2],'little'))
        assert [row[3][6] for row in records]==[8,1,11,12]+([13] if live else [])
        decision=records[3][3]
        ref,fp,length,digest=binding(wire)
        assert decision[48:56]==struct.pack('<HHI',6,1,125)
        assert decision[56:165]==ref+fp+length+digest+LE(f.operator)+bytes([1 if live else 2])
        assert decision[165:181]!=bytes(16)
        if live:
            permit=records[4][3]
            stamp=struct.unpack_from('<Q',permit,40)[0]
            assert permit[48:56]==struct.pack('<HHI',2,1,81) and permit[56:88]==decision[8:40]
            assert permit[88:104]!=bytes(16) and permit[104:121]==LE(0)+LE(stamp+90_000_000)+b'\x01'
        head=genesis
        for seq,(store,epoch,key,event) in enumerate(records,1):
            assert store+epoch+key==event[8:40]==STORE+LE(1)+LE(seq) and event[-32:]==head
            head=sha(b'warband.link.v1\0'+event[8:40]+head+sha(b'warband.event.v1\0'+event[:-32]))
        assert settled[0][2:5]==(STORE+LE(1)+LE(len(records))+head,b'',12 if live else 10)
        for same in (True,False):
            with server(f,'receipts',int(live)) as fresh:
                answer=b'approve' if same==live else b'reject'
                result=cli(f,wire,answer)
                assert result==((0,f'Recorded {STORE.hex()} 1 4') if same else (1,'DecisionConflict'))
                assert line(fresh)==('Recorded' if same else 'DecisionConflict')+' LiveGrant false'
                assert fresh.wait(timeout=10)==(0 if same else 1)
            assert snapshot()==settled and not list(directory.iterdir())
        emit(marker_approval=case,operator_uid=f.operator,decision_ref=decision[8:40].hex(),
             fingerprint=fp.hex(),projection=[1,int(live)],tip=settled[0][4],fresh_grant=False)


def run():
    for case in ('approve','reject','ref','fingerprint','length','digest','unauthorized','directory','role_change','stale','lost_reply','commit12','commit13'):
        approval_case(case)
