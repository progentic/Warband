"""Filesystem-returned WAL sync error in a production receipt import. Run in the Linux qualification scope."""
import contextlib
import fcntl
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from observe_volume_io import check_commit_steps, sqlite_steps, traced_import
from test_custody_denial import emit, limits, sha, STORE
from test_receipt_import import (OUT, LE, admin_frame, capture_files, event_and_pledge, fixture, hold_reader,
                                 inspect_wal, seal_capture, transaction_result)


class MountUnavailable(Exception):
    pass


@contextlib.contextmanager
def mounted(f, arm, out):
    path = f.db.parent
    if not Path('/dev/fuse').is_char_device():
        raise MountUnavailable('/dev/fuse unavailable')
    with (f.root/'daemon.log').open('w') as log:
        daemon = subprocess.Popen([OUT/'wal-sync-fs',path,arm],stdout=log,stderr=subprocess.STDOUT)
        try:
            until = time.monotonic()+8
            while not os.path.ismount(path):
                if daemon.poll() is not None:
                    message = (f.root/'daemon.log').read_text()
                    if 'Operation not permitted' in message or 'Permission denied' in message:
                        raise MountUnavailable(message)
                    raise AssertionError(message)
                assert time.monotonic()<until, 'FUSE mount timed out'
                time.sleep(.02)
            record = subprocess.check_output(['findmnt','-nM',path,'-o','ID,FSTYPE,OPTIONS'],text=True).strip()
            assert record.split()[1].startswith('fuse.') and out.stat().st_dev!=path.stat().st_dev
            yield record
        finally:
            if os.path.ismount(path):
                subprocess.run(['umount',path],check=True)
            if daemon.poll() is None:
                daemon.terminate()
            daemon.wait(timeout=8)
            assert not os.path.ismount(path)
            emit(unmounted=str(path))


def grade(out, fault, use_fuse):
    io = (out/'io.log').read_text().splitlines()
    assert any('mmap(' in l and 'MAP_SHARED' in l and 'active.db-shm>' in l and ' = 0x' in l for l in io)
    wal = [l for l in io if 'active.db-wal>' in l]
    writes = [l for l in wal if 'pwrite64(' in l]
    assert writes and all(re.search(r', (\d+), \d+\) = \1$',l) for l in writes),writes
    syncs = [l for l in wal if 'fsync(' in l or 'fdatasync(' in l]
    assert len(syncs)>=2 and syncs[0].endswith(' = 0')
    failure = [l for l in io if ' = -1 EIO' in l]
    assert failure==([syncs[-1]] if fault else [])
    sync = re.search(r'^(\d+)\s+[\d.]+ (f(?:data)?sync)\((\d+)<',syncs[-1])
    pid,call,fd = sync.groups()
    check_commit_steps(out/'sql.log',fault,pid,fd,call,len(syncs))
    if use_fuse:
        lines = [l.split() for l in (out/'filesystem.log').read_text().splitlines() if l.startswith('wal_')]
        marker, = [r for r in lines if r[0]=='wal_write' and r[-1]=='1']
        _, owner, handle, offset, length, written, _ = marker
        assert owner==pid and length==written=='24' and (int(offset)-32)%4120==0
        write, = [l for l in writes if l.endswith(f', 24, {offset}) = 24')]
        page, = [l for l in writes if l.endswith(f', 4096, {int(offset)+24}) = 4096')]
        assert io.index(syncs[0])<io.index(write)<io.index(page)<io.index(syncs[-1])
        prefix = 'wal_sync',pid,handle,str(int(call=='fdatasync'))
        callbacks = [r for r in lines if r[0]=='wal_sync']
        assert callbacks[0]==[*prefix,'-1','0']
        assert callbacks[-1]==[*prefix,offset,str(-5 if fault else 0)] and len(callbacks)==len(syncs)
        assert all(r[-1]=='0' for r in callbacks[:-1])
    return syncs


def exercise(files, arm, *, use_fuse=True):
    fault = arm=='fault'
    out = OUT/'wal-sync'/arm
    out.mkdir(parents=True)
    with fixture(seed_files=files) as (f,_,_), (mounted(f,arm,out) if use_fuse else contextlib.nullcontext('native')) as mount:
        before = f.verify()
        cp, receipt = before[2],before[5]
        assert cp[:32]==STORE+LE(1)+LE(0) and before[3:5]==(b'',2) and receipt
        with hold_reader(f):
            with f.db.open('rb') as held:
                fcntl.flock(held,fcntl.LOCK_EX|fcntl.LOCK_NB)
                f.run('LockUnavailable',allow=False)
            assert (f.db.parent/'active.db-shm').stat().st_size>0 and f.rows()==[[],[],[]]
            original = inspect_wal(Path(str(f.db)+'-wal'))
            assert original['size']==0
            with sqlite_steps(f.root/'importer',out/'sql.log',sync_calls=True) as attached:
                assert attached, (out/'sql.log').read_text()
                result = traced_import(f,STORE,out/'io.log',mapping=True)
            assert (result.returncode,result.stdout.strip())==((1,'AttestationUncertain') if fault else (0,'Ready')),result
            hashes,owners,sidecars = capture_files(f,out)
            if use_fuse: shutil.copyfile(f.root/'daemon.log',out/'filesystem.log')
            for p in out.glob('*.log'): hashes[p.name]=sha(p.read_bytes()).hex()
            digest = seal_capture(out,hashes,dict(arm=arm,mount=mount,kernel=os.uname().release,owners=owners,
                sidecars=sidecars,baseline_wal=original,seed={n:sha(b).hex() for n,b in files.items()},result=result.stdout.strip(),
                binaries={b.name:sha(b.read_bytes()).hex() for b in (OUT/'wal-sync-fs',f.root/'importer',f.root/'custodian')}))
            emit(arm=arm,inventory_sha256=digest,syncs=grade(out,fault,use_fuse))
            view=f.verify()
            wal=inspect_wal(out/'journal/active.db-wal')
            if fault:
                pending=view[3]
                assert view[2]==cp and view[4]==3 and pending[:72]==cp+LE(1)
                assert pending[72:104]==sha(b'warband.link.v1\0'+STORE+LE(1)+LE(1)+cp[32:]+pending[104:])
                assert (out/'data/head').read_bytes()==files['data/head']
                assert (out/'data/history').read_bytes()==files['data/history']+admin_frame(1,pending,3,files['data/history'][-32:])
                outcome,rows=transaction_result(f,out,cp[32:],receipt,view,True)
                assert outcome in ('PendingConfirmation','PendingEventMissing'),(outcome,wal)
                assert (wal['last_commit']>0)==(outcome=='PendingConfirmation'),wal
                emit(observed=outcome,wal=wal)
            else:
                assert view[3:5]==(b'',4) and view[2][:32]==STORE+LE(1)+LE(1) and wal['last_commit']>0
                events,bindings,marks=f.rows()
                stamp=int.from_bytes(events[0][3][40:48],'little')
                wire,pledge=event_and_pledge(cp[32:],receipt,stamp)
                assert events==[(STORE,LE(1),LE(1),wire)] and bindings==[(STORE,receipt[11:19],receipt[-32:],LE(1),LE(1))]
                assert marks==[(STORE,receipt[11:19])] and view[2]==STORE+LE(1)+pledge[64:104]
        if not fault:
            rows=f.rows()
            assert f.run('Ready')=='Ready' and f.rows()==rows and f.verify()==view
            return
    retained = {str(p.relative_to(out)):p.read_bytes() for d in ('data','journal') for p in (out/d).iterdir()}
    with fixture(seed_files=retained) as (f,_,_):
        replay=shutil.copy2(OUT/'reconcile/replay-noop',f.root/'replay')
        def projection(state, count):
            args=[replay,f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1']
            proc=subprocess.run(args,user=f.runtime,group=f.runtime,extra_groups=[],capture_output=True,text=True,check=True,timeout=65)
            assert proc.stdout==f'Journal {state} OutstandingReceipts {count}\n'
        projection(outcome,1)
        assert f.verify()==view and f.rows()==rows
        exact = outcome=='PendingConfirmation'
        assert f.run(outcome,allow=exact)==outcome
        after=f.verify()
        assert after[4]==3+int(exact) and f.rows()==rows
        if exact:
            assert after[3]==b'' and after[2]==STORE+LE(1)+pending[64:104]
        else:
            assert after==view
        history=retained['data/history']
        if exact: history+=admin_frame(2,pending,4,history[-32:])
        repeat='Ready' if exact else outcome
        assert f.run(repeat,allow=exact)==repeat and f.verify()==after and f.rows()==rows
        assert (f.root/'data/history').read_bytes()==history
        projection(repeat,int(not exact))
        emit(recovered=outcome,repeat=repeat,tip=after[4],inventory_sha256=digest)


if __name__=='__main__':
    assert os.getuid()==0 and limits('self')==(256*1024*1024,0)
    with fixture() as (f,_,_):
        assert f.query('PRAGMA journal_mode=WAL')==[('wal',)]
        files={str(p.relative_to(f.root)):p.read_bytes() for d in ('data','journal') for p in (f.root/d).iterdir()}
    try:
        exercise(files,'healthy')
    except MountUnavailable as error:
        if sys.argv[1:]!=['--hosted']: raise
        exercise(files,'native-healthy',use_fuse=False)
        emit(qualification='healthy observer only',mount_unavailable=str(error))
    else:
        emit(feasibility='passed')
        if sys.argv[1:]!=['--healthy-only']:
            exercise(files,'fault')
