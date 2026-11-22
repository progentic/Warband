"""Environmental ENOSPC on a bounded shared tmpfs; run inside the Linux runtime scope."""
import contextlib
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import time

from observe_volume_io import custody_calls, sqlite_steps, traced_import
from test_custody_denial import STORE, denied, emit, limits, service, sha
from test_receipt_import import OUT, ENROLL, LE, admin_frame, capture_files, event_and_pledge, fixture, hold_reader, inspect_wal, seal_capture, captured_rows, verified_tmpfs_mount


@contextlib.contextmanager
def volume(root):
    assert root.parent==Path('/var/lib') and root.name.startswith('warband-import-')
    vol = root/'volume'
    vol.mkdir()
    paths = [vol,root/'data',root/'journal']
    with contextlib.ExitStack() as mounts:
        mounts.enter_context(verified_tmpfs_mount(['-t','tmpfs','-o','size=8M,nr_inodes=2048,nodev,nosuid,noexec','tmpfs'],vol))
        for target in paths[1:]:
            src,st = vol/target.name,target.stat()
            src.mkdir()
            os.chown(src,st.st_uid,st.st_gid)
            src.chmod(st.st_mode & 0o777)
            mounts.enter_context(verified_tmpfs_mount(['--bind',src],target))
        assert all(p.stat().st_dev==vol.stat().st_dev for p in paths) and root.stat().st_dev!=vol.stat().st_dev
        yield
    emit(unmounted=[str(p) for p in paths])


def space(vol):
    st = os.statvfs(vol)
    return dict(time_ns=time.time_ns(),total=st.f_blocks*st.f_frsize,free=st.f_bavail*st.f_frsize,
                unit=st.f_frsize,free_inodes=st.f_favail)


def run_case(case):
    out = OUT/'volume-exhaustion'/case
    out.parent.mkdir(parents=True,exist_ok=True)
    out.mkdir()  # Fresh trace and inventory for every arm.
    with fixture(storage_mount=volume) as (f, _, _):
        vol,db = f.root/'volume',f.db
        assert not out.resolve().is_relative_to(vol) and out.stat().st_dev!=vol.stat().st_dev
        assert f.query('PRAGMA journal_mode=WAL')==[('wal',)]
        wal = Path(str(db)+'-wal')
        history,head = f.root/'data/history',f.root/'data/head'
        args = [f.root/'importer',db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1','0','-']
        with hold_reader(f):
            with sqlite_steps(args[0],out/'healthy-sql.log') as attached:
                healthy = traced_import(f,STORE,out/'healthy-io.log')
            assert (healthy.returncode,healthy.stdout.strip())==(0,'Ready'),healthy
            def steps(path):
                return [line.split(' ',3)[1:] for line in path.read_text().splitlines() if line.startswith('step ')]
            good = steps(out/'healthy-sql.log')
            qualified = attached and all(any(row[:2]==['101','101'] and row[2].startswith(sql) for row in good)
                       for sql in ('INSERT INTO events','INSERT INTO denial_imports','INSERT INTO import_watermarks','COMMIT'))
            emit(arm=case,observer_qualified=qualified)
            denied(f.call(4,ENROLL,denied_admin=True))
            initial = space(vol)
            f.run('Ready')
            cost = initial['free']-space(vol)['free']
            denied(f.call(4,ENROLL,denied_admin=True))
            if case=='history':
                while (-history.stat().st_size)%initial['unit'] >= 251:
                    f.run('Ready')
                    denied(f.call(4,ENROLL,denied_admin=True))
                    assert history.stat().st_size<80*1024
            base, oldhead, rows = history.read_bytes(),head.read_bytes(),f.rows()
            before = f.verify()
            receipt = f.verify(int.from_bytes(rows[2][0][1],'little'))[5]
            assert receipt and before[3]==b'' and cost>0
            baseline_wal = inspect_wal(wal)
            leave = cost if case=='head' else 0
            mount_record = [subprocess.check_output(['findmnt','-nM',p,'-o','ID,FSTYPE,OPTIONS'],text=True).strip() for p in (vol,history.parent,db.parent)]
            stats = {'baseline':space(vol)}
            with (vol/'filler').open('xb') as filler:
                os.posix_fallocate(filler.fileno(),0,space(vol)['free']-leave)
                stats['filled'] = space(vol)
                assert stats['filled']['free']==leave and stats['filled']['free_inodes']>10
                with sqlite_steps(args[0],out/'fault-sql.log') as fault_attached, custody_calls(f.custodian_pid,out/'custody-io.log'):
                    with ThreadPoolExecutor(1) as pool:
                        proc = pool.submit(traced_import,f,STORE,out/'fault-io.log')
                        while not proc.done():
                            if any(' = -1 ENOSPC' in p.read_text() for p in (out/'fault-io.log',out/'custody-io.log') if p.exists()):
                                break
                            time.sleep(.002)
                        stats['first_observation'] = space(vol)
                        failed = proc.result()
                    stats['failure'] = space(vol)
                hashes,owners,sidecars = capture_files(f,out,include_tmp=True)
                traces = (out/'custody-io.log').read_text()+(out/'fault-io.log').read_text()
                traces = re.sub(r'<((?:\\x[0-9a-f]{2})+)>',
                                lambda m:'<'+bytes.fromhex(m[1].replace('\\x','')).decode()+'>',traces)
                failures = [l for l in traces.splitlines() if ' = -1 ENOSPC' in l]
                sql = steps(out/'fault-sql.log') if qualified and fault_attached else []
                wal_state = inspect_wal(out/'journal/active.db-wal')
                meta = dict(arm=case,kernel=os.uname().release,mounts=mount_record,stats=stats,leave=leave,
                            filler_bytes=os.fstat(filler.fileno()).st_blocks*512,observer_qualified=qualified and fault_attached,owner=owners,sidecars=sidecars,
                            baseline_wal=baseline_wal,wal=wal_state,sql=sql,errors=failures,result=failed.stdout.strip(),
                            source=subprocess.check_output(['git','-c',f'safe.directory={Path.cwd()}','rev-parse','HEAD'],text=True).strip(),
                            binaries={p.name:sha(p.read_bytes()).hex() for p in (args[0],f.root/'custodian')})
                assert meta['filler_bytes']==stats['baseline']['free']-leave
                for p in out.glob('*.log'): hashes[p.name]=sha(p.read_bytes()).hex()
                inventory = seal_capture(out,hashes,meta)
                emit(volume_capture=case,inventory_sha256=inventory,failures=failures)
            (vol/'filler').unlink()
            stats['relieved'] = space(vol)
            assert (failed.returncode,failed.stdout.strip())==(1,'AttestationUncertain'),failed
            wanted = {'history':history,'head':f.root/'data/head.tmp','wal':wal}[case]
            assert any(str(wanted)+'>' in l and re.search(r'\b(pwrite64|write)\(',l) for l in failures),failures
            if case=='head':
                assert (out/'data/head.tmp').read_bytes()==b''
            if case=='wal':
                assert baseline_wal['valid_frames']>0 and any(int(l.split(') =')[0].rsplit(',',1)[1])>=32 for l in failures if 'pwrite64(' in l and str(wal)+'>' in l)
            if case!='history':
                completed = [l for l in traces.splitlines() if str(history)+'>' in l and l.endswith(' = 251')]
                synced = [l for l in traces.splitlines() if 'fsync(' in l and str(history)+'>' in l and l.endswith(' = 0')]
                assert len(completed)==len(synced)==(2 if case=='head' else 1)
            assert stats['first_observation']['free']==stats['failure']['free']==0 and stats['relieved']['free']>0
        # Classify the captured history and a fresh snapshot on a disposable copy before recovery.
        actual = [sorted(t) for t in captured_rows(f.root,out)]
        raw = (out/'data/history').read_bytes()
        assert raw.startswith(base) and (out/'data/head').read_bytes()==oldhead
        tail = raw[len(base):]
        seq = len(rows[0])+1
        if actual==[sorted(t) for t in rows]:
            if len(tail)<251:
                write, = [l for l in traces.splitlines() if str(history)+'>' in l and ', 251) =' in l]
                attempted = bytes.fromhex(write.split('"')[1].replace('\\x',''))
                assert len(attempted)==251 and attempted==admin_frame(1,attempted[83:-32],before[4]+1,base[-32:])
                assert tail==attempted[:len(tail)] and len(tail)==int(write.split(' = ')[-1])
                observed='Ready'
            else:
                pledge=tail[83:-32]
                assert tail==admin_frame(1,pledge,before[4]+1,base[-32:]) and pledge[:72]==before[2]+LE(seq)
                assert pledge[72:104]==sha(b'warband.link.v1\0'+STORE+LE(1)+LE(seq)+before[2][32:]+pledge[104:])
                observed='PendingEventMissing'
        else:
            added, = set(actual[0])-set(rows[0])
            event,pledge=event_and_pledge(before[2][32:],receipt,struct.unpack_from('<Q',added[3],40)[0],seq)
            ref=(STORE,LE(1),LE(seq)); ordinal=receipt[11:19]
            assert actual==[sorted(rows[0]+[(*ref,event)]),sorted(rows[1]+[(STORE,ordinal,receipt[-32:],*ref[1:])]),[(STORE,ordinal)]]
            pending=admin_frame(1,pledge,before[4]+1,base[-32:])
            assert tail==pending+admin_frame(2,pledge,before[4]+2,pending[-32:])
            observed='HeadPublicationPending'
        emit(arm=case,observed=observed,space=stats,sql_errors=[r for r in sql if int(r[0]) not in (100,101)])
        assert observed=={'wal':'PendingEventMissing','history':'Ready','head':'HeadPublicationPending'}[case]
        recovery=contextlib.nullcontext() if case=='wal' else service(f.root,f.root/'custodian',f.custodian,f.runtime,f.operator)
        with recovery:
            view=f.verify()
            assert view[4]==before[4]+{'history':0,'wal':1,'head':2}[case]
            assert [sorted(t) for t in f.rows()]==actual
            assert history.read_bytes()==(base if case=='history' else raw)
            assert (head.read_bytes()==oldhead)==(case!='head')
            if case=='wal':
                assert view[3]==pledge and f.run(observed,allow=False)==observed and f.verify()==view
                assert wal_state['last_commit']==baseline_wal['last_commit']
                if qualified and fault_attached: assert any(r[2]=='COMMIT' and int(r[0]) in (10,13) for r in sql),sql
            else:
                assert f.run('Ready')=='Ready' and f.verify()[4]==before[4]+2
                assert len(f.rows()[0])==len(rows[0])+1
            replay=shutil.copy2(OUT/'reconcile/replay-noop',f.root/'replay')
            p=subprocess.run([replay,*args[1:6]],user=f.runtime,group=f.runtime,extra_groups=[],capture_output=True,text=True)
            assert (p.returncode,p.stdout.splitlines())==(0,[f"Journal {'PendingEventMissing' if case=='wal' else 'Ready'} OutstandingReceipts {int(case=='wal')}"])
        emit(case='volume_exhaustion',arm=case,inventory_sha256=inventory,observed=observed)


if __name__=='__main__':
    assert os.getuid()==0 and limits('self')==(256*1024*1024,0)
    for arm in ('history','head','wal'): run_case(arm)
