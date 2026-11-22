"""Inspect an isolated copy of an inventoried rehearsal capture. The operator decides disposition."""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

from test_custody_denial import STORE, limits, sha
from test_receipt_import import ENROLL, LE, OUT, admin_frame, event_and_pledge, fixture


def inventory(bundle, expected):
    assert not bundle.is_symlink() and not any(p.is_symlink() for p in bundle.rglob('*'))
    sums = (bundle/'SHA256SUMS').read_bytes()
    assert sha(sums).hex()==expected, 'inventory differs from the capture log'
    allowed = {'capture.json','data/head','data/history','journal/active.db',
               'journal/active.db-wal','journal/active.db-shm','journal/active.db-journal'}
    files = {}
    for line in sums.decode().splitlines():
        digest,name = line.split('  ')
        assert name in allowed and name not in files
        files[name] = (bundle/name).read_bytes()
        assert sha(files[name]).hex()==digest,name
    assert set(files)=={str(p.relative_to(bundle)) for p in bundle.rglob('*') if p.is_file()}-{'SHA256SUMS'}
    meta = json.loads(files.pop('capture.json'))
    assert set(meta['sidecars'])=={'journal/active.db'+ext for ext in ('-wal','-shm','-journal')}
    assert all(present==(name in files) for name,present in meta['sidecars'].items())
    return files,meta


def inspect(bundle, expected):
    assert os.getuid()==0 and limits('self')==(256*1024*1024,0)
    inputs,meta = inventory(bundle,expected)
    with fixture(seed_files=inputs) as (f,_,_):
        assert all((f.root/name).read_bytes()==data for name,data in inputs.items())
        verified = f.verify()
        _,_,cp,pending,tip,receipt = verified
        history,head = inputs['data/history'],inputs['data/head']
        assert history.startswith(receipt) and receipt[6]==5 and receipt[11:19]==LE(1)
        genesis = admin_frame(3,ENROLL+LE(meta['operator_uid']),2,receipt[-32:])
        assert cp==STORE+LE(1)+LE(0)+sha(b'warband.genesis.v1\0'+ENROLL)
        body = b'WBHD'+struct.pack('<H',1)+cp+genesis[-32:]
        assert head==body+sha(b'warband.head.v1\0'+body)
        rows = f.rows()
        ref = STORE,LE(1),LE(1)
        if pending:
            assert 'pending_record_hash' in meta
            state,provenance = 'PendingEventMissing','process kill after durable Prepare, before SQLite transaction'
            assert tip==3 and rows==[[],[],[]]
            assert pending[:72]==cp+LE(1) and pending[72:104]==sha(b'warband.link.v1\0'+b''.join(ref)+cp[32:]+pending[104:])
            frame = admin_frame(1,pending,3,genesis[-32:])
            assert history==receipt+genesis+frame and frame[-32:].hex()==meta['pending_record_hash']
            digest = pending[104:]
            replay_line = 'Journal PendingEventMissing OutstandingReceipts 1'
            replay_rc = 0
        else:
            state,provenance = 'UnattestedTail',meta['construction']
            assert tip==2 and history==receipt+genesis
            wire,pledge = event_and_pledge(cp[32:],receipt,456)
            assert rows==[[(*ref,wire)],[(STORE,LE(1),receipt[-32:],*ref[1:])],[(STORE,LE(1))]]
            digest = pledge[104:]
            replay_line,replay_rc = 'Failure IntegrityFault UnattestedTail',1
        assert f.run(state,allow=False)==state
        replay = shutil.copy2(OUT/'reconcile/replay-noop',f.root/'replay')
        p = subprocess.run([replay,f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1'],
                           user=f.runtime,group=f.runtime,extra_groups=[],capture_output=True,text=True,timeout=65)
        assert (p.returncode,p.stdout.splitlines())==(replay_rc,[replay_line]),(p.stdout,p.stderr)
        assert f.verify()==verified and f.rows()==rows
        assert (f.root/'data/history').read_bytes()==history and (f.root/'data/head').read_bytes()==head
    assert inventory(bundle,expected)==(inputs,meta)
    report = dict(case=state,provenance=provenance,source=meta['source'],inventory_sha256=expected,tip=tip,
                  checkpoint=cp.hex(),receipt_hash=receipt[-32:].hex(),pending_record_hash=frame[-32:].hex() if pending else None,
                  event_ref=b''.join(ref).hex(),event_digest=digest.hex(),event_rows=len(rows[0]),
                  replay=p.stdout.strip(),preserved=True)
    print(json.dumps(report,sort_keys=True),flush=True)


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle',type=Path)
    parser.add_argument('inventory_sha256')
    args = parser.parse_args()
    inspect(args.bundle,args.inventory_sha256)
