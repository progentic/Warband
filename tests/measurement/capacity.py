"""Run in a disposable x64-review systemd scope (MemoryMax=256M, MemorySwapMax=0)."""
import contextlib
import gzip
import json
import os
from pathlib import Path
import pwd
import shutil
import socket
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'integration/linux'))
from test_custody_denial import STORE, as_user, limits, request, service
from test_receipt_import import ENROLL, OUT

def snapshot(root, db):
    wal = Path(str(db)+'-wal')
    sizes = [(root/'data/history').stat().st_size, db.stat().st_size, wal.stat().st_size if wal.exists() else None]
    uri = db.as_uri()+('?mode=ro' if sizes[2] is not None else '?immutable=1')
    with contextlib.closing(sqlite3.connect(uri,uri=True)) as conn:
        counts = [conn.execute('SELECT count(*) FROM '+t).fetchone()[0] for t in ('events','denial_imports')]
        mark = conn.execute('SELECT last_imported_ordinal FROM import_watermarks').fetchone()
    return dict(sizes=sizes, head=(root/'data/head').read_bytes().hex(), counts=counts,
                mark=int.from_bytes(mark[0],'little') if mark else 0)

def predict(n):
    return (25*n*n+33*n)//2+3

def sample(n, generator_left):
    assert predict(n)<80000 and (n+1)*(2*(1+3*n)+1)+n<80000
    used = {p.pw_uid for p in pwd.getpwall()}
    cust,runtime,operator = [u for u in range(50000,60000) if u not in used][:3]
    with tempfile.TemporaryDirectory(prefix='warband-cap-',dir='/var/lib') as name:
        root = Path(name)
        root.chmod(0o755)
        for part,uid,mode in [('data',cust,0o700),('endpoints',cust,0o755),('journal',operator,0o555)]:
            path = root/part
            path.mkdir()
            os.chown(path,uid,uid)
            path.chmod(mode)
        for binary in ('custodian','reconcile-custody'):
            shutil.copy2(OUT/'capacity'/binary,root/binary)
        db = root/'journal/store.db'
        log = root/'meter'
        log.touch(mode=0o600)
        with service(root,root/'custodian',cust,runtime,operator,stderr_path=log), log.open() as stream:
            def drain():
                rows = []
                for line in stream.readlines():
                    tag,*row = line.split()
                    assert tag=='CAP',line
                    rows.append(list(map(int,row)))
                return rows

            def reconcile():
                args = [root/'reconcile-custody',db,root/'endpoints/runtime.sock',str(cust),STORE.hex(),'1','0','-']
                def invoke():
                    proc = subprocess.run(args,capture_output=True,timeout=65)
                    assert proc.returncode==0 and proc.stdout.strip()==b'Ready', (proc.stdout,proc.stderr)
                    return proc.stderr
                tag,*row = as_user(runtime,invoke).split()
                assert tag==b'CAP'
                return dict(client=list(map(int,row)),server=drain())

            def generate():
                wire = b'WBCR'+struct.pack('<HBI',1,4,len(ENROLL))+ENROLL
                deadline = time.monotonic()+generator_left
                for _ in range(n):
                    assert time.monotonic()<deadline
                    with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as sock:
                        sock.settimeout(30)
                        sock.connect(str(root/'endpoints/operator.sock'))
                        assert struct.unpack('3i',sock.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))[1]==cust
                        sock.sendall(wire)
                        sock.shutdown(socket.SHUT_WR)
                        reply = sock.makefile('rb').read(491)
                        assert len(reply)==151 and reply[:4]==b'WBRS' and reply[7:9]==b'\x0f\0' and any(reply[45:77])
                return b'ok'

            assert request(root,'operator.sock',operator,4,ENROLL,cust)[0]==0
            drain()
            os.chown(db.parent,runtime,runtime)
            db.parent.chmod(0o700)
            subprocess.run([OUT/'provision-store',db],check=True)
            os.chown(db,runtime,runtime)
            baseline = reconcile()
            a = snapshot(root,db)
            start = time.monotonic()
            assert as_user(runtime,generate)==b'ok'
            generated_seconds = time.monotonic()-start
            generation = drain()
            b = snapshot(root,db)
            assert a['counts']==b['counts']==[0,0] and a['head']==b['head'] and len(generation)==n
            assert b['sizes'][0]-a['sizes'][0]==203*n
            imported = reconcile()
            c = snapshot(root,db)
            assert c['counts']==[n,n] and c['mark']==n+1 and int.from_bytes(bytes.fromhex(c['head'])[30:38],'little')==n
            assert c['sizes'][0]-b['sizes'][0]==502*n
            noop = reconcile()
            assert snapshot(root,db)==c and imported['client'][-1]==predict(n)
            assert len(imported['server'])==3*n+1 and len(noop['server'])==n+1
            return dict(n=n,generator_seconds=generated_seconds,A=a,B=b,C=c,baseline=baseline,denials=generation,imported=imported,noop=noop)

def oracle(row):
    assert row['baseline']==dict(client=[0,0,0,0,0,3,3],server=[[3,1,1,0]])
    assert row['denials']==[[4,1,0,0]]
    assert row['imported']==dict(client=[1,1,0,0,1,30,32],server=[[3,2,2,1],[1,2,0,0],[2,3,0,0],[3,4,4,0]])
    assert row['noop']==dict(client=[1,1,1,0,0,18,19],server=[[3,4,2,1],[3,4,4,0]])

if __name__=='__main__':
    assert os.getuid()==0 and limits('self')==(256*1024*1024,0)
    # Each complete gzip member is durable output from one store, including its raw request counts.
    output = Path(sys.argv[1])
    assert not output.exists()
    totals = list(map(int,sys.argv[2:]))
    assert totals and totals[0]==1 and all(t in (1,100,1000,10000) for t in totals)
    for total in totals:
        for rep in range(1,2 if total==1 else 4):
            generator_left = 600
            for segment in range(1 if total==1 else total//50):
                row = dict(total=total,rep=rep,segment=segment,**sample(min(50,total),generator_left))
                generator_left -= row['generator_seconds']
                with gzip.open(output,'at') as f:
                    f.write(json.dumps(row,separators=(',',':'))+'\n')
                if total==1: oracle(row)
            print('completed',total,rep,flush=True)
