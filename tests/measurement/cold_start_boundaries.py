"""Qualify cold recovery on isolated copies, using production enrollment and denial payloads."""
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time
import uuid

from test_custody_denial import STORE, ZERO, denied, emit, request, sha
from test_noop_gate import history_inventory
from test_receipt_import import ENROLL, LE, OUT, admin_frame, fixture

CAP = 8*1024*1024
NORMAL = OUT/'custodian/normal/custodian'
PROBE = OUT/'capacity/cold-limits'


def crafted(reason_length, count, operator, rejection):
    enroll = ENROLL[:40]+struct.pack('<H',reason_length)+b'r'*reason_length
    genesis = admin_frame(3,enroll+LE(operator),1,ZERO)
    checkpoint = STORE+LE(1)+LE(0)+sha(b'warband.genesis.v1\0'+enroll)
    head = b'WBHD\x01\0'+checkpoint+genesis[-32:]
    buf = bytearray(genesis)
    for ordinal in range(2,count+2):
        buf.extend(admin_frame(5,rejection,ordinal,buf[-32:]))
    history = bytes(buf)
    frames, err = history_inventory(history)
    assert err is None and len(frames)==count+1 and history[83:len(genesis)-32]==enroll+LE(operator)
    assert all(k==5 and sz==203 and history[o+83:o+sz-32]==rejection for _,k,o,sz in frames[1:])
    return history,head+sha(b'warband.head.v1\0'+head),count+1


def boot(root, users, mode, expected, label, retained=None):
    history,head,tip = expected
    custodian,runtime,operator = users
    endpoints = root/'endpoints'
    assert not list(endpoints.iterdir())
    unit = 'warband-cold-'+uuid.uuid4().hex
    args = ['systemd-run','--quiet','--wait','--collect','--pipe','--service-type=exec','--unit',unit,
            '-p','MemoryMax=32M','-p','MemorySwapMax=0','/usr/bin/setpriv',f'--reuid={custodian}',
            f'--regid={custodian}','--clear-groups','--no-new-privs',root/('normal' if mode is None else 'probe'),
            root.name,str(runtime),str(operator),STORE.hex()]
    if mode is not None:
        args.append(str(mode))
    with (root/'data/head').open('rb') as held, (root/'log').open('w+') as log:
        start = time.monotonic_ns()
        p = subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT)
        ready = False
        try:
            while p.poll() is None:
                if (endpoints/'operator.sock').is_socket():
                    assert (endpoints/'runtime.sock').is_socket()
                    reply = request(root,'runtime.sock',runtime,3,STORE+LE(1)+LE(0),custodian)
                    assert (reply[0],reply[2],reply[3],reply[4])==(0,head[6:70],b'',tip), reply[:5]
                    ready = True
                    break
                assert time.monotonic_ns()-start < 80_000_000_000, label
                time.sleep(.02)
            elapsed = time.monotonic_ns()-start
        finally:
            if p.poll() is None:
                subprocess.run(['systemctl','stop',unit],check=True)
            p.wait(timeout=10)
        log.seek(0)
        trace = log.read().splitlines()
        startup = trace[:trace.index('LISTEN')+1] if 'LISTEN' in trace else trace
        old, new = os.fstat(held.fileno()), (root/'data/head').stat()
        replaced = not os.path.samestat(old,new)
        row = dict(case=label,mode=mode,bytes=len(history),tip=tip,ready=ready,exit=p.returncode,
                   elapsed_ns=elapsed,replaced=replaced,head_inodes=[old.st_ino,new.st_ino],head_sha256=sha(head).hex(),history_sha256=sha(history).hex(),trace=startup)
        with (OUT/'cold-start-boundaries.jsonl').open('a') as out:
            out.write(json.dumps(row)+'\n')
        assert held.read()==head==(root/'data/head').read_bytes()
        assert sorted(p.name for p in (root/'data').iterdir())==['head','history']
        assert (root/'data/history').read_bytes()==(history if retained is None else retained)
        if ready:
            assert replaced and (mode is None or 'LISTEN' in startup)
            for path in endpoints.iterdir():
                assert path.is_socket()
                path.unlink()
        else:
            assert p.returncode==4 and not list(endpoints.iterdir()) and 'LISTEN' not in startup, row
        return row


def qualify():
    (OUT/'cold-start-boundaries.jsonl').write_text('')
    with fixture() as (f, _, _):
        denied(f.call(4,ENROLL,denied_admin=True))
        small = ((f.root/'data/history').read_bytes(),(f.root/'data/head').read_bytes(),3)
        receipt = f.verify(2)[5]
        assert len(receipt)==203 and receipt[99:107]==LE(1)
        users = f.custodian,f.runtime,f.operator
        journal = {p.name:p.read_bytes() for p in f.db.parent.iterdir()}

    emit(kernel=os.uname().release,normal_sha256=sha(NORMAL.read_bytes()).hex(),probe_sha256=sha(PROBE.read_bytes()).hex(),
         enrollment=ENROLL.hex(),operator=users[2],receipt_payload=receipt[83:-32].hex())

    symbols = subprocess.check_output(['nm','-an',NORMAL],text=True)
    address, = [l.split()[0] for l in symbols.splitlines() if l.endswith(' main::workspace')]
    def run(label, image, mode, *, ready=None, replaced=False, retained=None):
        with tempfile.TemporaryDirectory(dir='/var/lib',prefix='warband-bound-') as tmp:
            root = Path(tmp)
            root.chmod(0o755)
            for name,uid,perm in [('data',users[0],0o700),('endpoints',users[0],0o755),('journal',users[1],0o700)]:
                d = root/name
                d.mkdir(mode=perm)
                os.chown(d,uid,uid)
            shutil.copy2(NORMAL,root/'normal')
            shutil.copy2(PROBE,root/'probe')
            def install(name,data,uid):
                path = root/name
                path.write_bytes(data)
                path.chmod(0o600)
                os.chown(path,uid,uid)
            for name,data in journal.items():
                install('journal/'+name,data,users[1])
            def restore(store):
                install('data/history',store[0],users[0])
                install('data/head',store[1],users[0])
            restore(image)
            row = boot(root,users,mode,image,label,retained)
            if mode is not None:
                assert f'ARENA {int(address,16)%64} {CAP}' in row['trace'],row
            if ready is not None:
                assert row['ready']==ready,row
            if not row['ready']:
                assert row['replaced']==replaced,row
                restore(small)
                assert boot(root,users,None,small,label+'-restore')['ready']
            assert {p.name:p.read_bytes() for p in (root/'journal').iterdir()}==journal
            return row

    def large(n, reason):
        return crafted(reason,n,users[2],receipt[83:-32])

    full = large(41_322,77)
    assert len(full[0])==CAP
    for label,image in [('B1',full),('B2',(full[0]+b'W',*full[1:]))]:
        for _ in range(2):
            ordinary = run(label,image,None,ready=False)
            row = run(label,image,0,ready=ordinary['ready'])
            trace = row['trace']
            assert trace.count('SIZE '+str(len(image[0])))==1 and not any(t.startswith('TRIM') for t in trace)
            allocations = [t for t in trace if t.startswith('ALLOC read_history_bytes ')]
            if label=='B2':
                assert not allocations and not any(t.startswith(('READ','VALID')) for t in trace)
            else:
                assert len(allocations)==1 and int(allocations[0].split()[2])==CAP
                if 'READ 8388608 0' in trace:
                    assert 'VALID MemoryLimitExceeded 0' in trace
                else:
                    assert allocations[0].endswith('Out_Of_Memory'),trace

    # Measure the map allocation on the small history, then bracket its actual boundary.
    witness = run('A-sizing',small,0,ready=True)
    allocations = [l.split() for l in witness['trace'] if l.startswith('ALLOC ')]
    assert len(allocations)>=2,allocations
    map_bytes = int(allocations[-1][5])-int(allocations[0][5])
    n = (CAP-map_bytes-512-165)//203
    low, high = 1,min(1024,CAP-166-203*n)
    def arena(reason,mode,ready=None):
        image = large(n,reason)
        assert len(image[0])<CAP
        row = run('A-'+str(reason),image,mode,ready=ready)
        if mode is not None:
            status = 'Consistent '+str(image[2]) if row['ready'] else 'MemoryLimitExceeded 0'
            assert 'READ '+str(len(image[0]))+' 0' in row['trace'] and 'VALID '+status in row['trace'],row
            maps = [l.split() for l in row['trace'] if l.startswith('ALLOC validate_custody_history ')]
            assert len(maps)==1 and int(maps[0][3])==64 and int(maps[0][4])==len(image[0]),row
            assert maps[0][-1]==('None' if row['ready'] else 'Out_Of_Memory'),row
        return row['ready']
    assert arena(low,0,True) and not arena(high,0,False)
    while high-low>1:
        mid = (low+high)//2
        if arena(mid,0):
            low = mid
        else:
            high = mid
    for mode in (None,0):
        arena(low,mode,True)
        for _ in range(2):
            arena(high,mode,False)
    emit(arena_frames=n+1,last_ready_bytes=165+low+203*n,first_refused_bytes=165+high+203*n)

    run('T-control',small,None,ready=True)
    row = run('T1',small,1,ready=True)
    assert [l for l in row['trace'] if l.startswith('CLOCK')]==['CLOCK 2 59999','CLOCK 3 59999']
    torn = (small[0]+admin_frame(5,receipt[83:-32],4,small[0][-32:])[:83],*small[1:])
    row = run('T1-torn',torn,1,ready=True,retained=small[0])
    assert [l for l in row['trace'] if l.startswith('CLOCK')]==[f'CLOCK {site} 59999' for site in (1,2,3)]
    assert f'TRIM {len(small[0])}' in row['trace']
    for mode in (2,3,4,5):
        for _ in range(2):
            row = run('T3' if mode==5 else 'T2',torn if mode==2 else small,mode,ready=False,replaced=mode==4)
            clock = [l for l in row['trace'] if l.startswith('CLOCK')]
            if mode==5:
                assert len(clock)==1 and clock[0].startswith('CLOCK 2 ') and int(clock[0].split()[-1])>=60_000
                assert row['elapsed_ns']>=60_000_000_000
            else:
                assert clock==(['CLOCK 2 59999'] if mode==4 else [])+[f'CLOCK {mode-1} 60000'],row
            assert not any(l.startswith('TRIM') for l in row['trace'])
    emit(cold_start_boundaries='passed',inventory_sha256=sha((OUT/'cold-start-boundaries.jsonl').read_bytes()).hex())
