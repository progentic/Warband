"""Single-history cold recovery, measured on real WBCR traffic and confirmed SQLite imports."""
import json
import select
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'integration/linux'))
from test_custody_denial import STORE, denied, emit, limits, service, sha
from test_noop_gate import confirmed_events, history_inventory
from test_receipt_import import ENROLL, LE, OUT, fixture
from capacity import predict


def sample(n, rep):
    tip = 1+3*n
    exchange = (n+1)*(2*tip+1)
    costs = [predict(n), exchange+n, exchange+3*n]
    assert max(costs)<80_000
    emit(preflight=dict(receipts=n,frames=tip,events=n,import_reconcile_replay=costs))
    signal.alarm(600)
    started = time.monotonic_ns()
    with fixture() as (f, genesis, first):
        def invoke(path, args=()):
            binary = shutil.copy2(path,f.root/path.name)
            return subprocess.run([binary,f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1',*args],
                                  user=f.runtime,group=f.runtime,extra_groups=[],capture_output=True,text=True,check=True,timeout=65)
        hashes = [first[-32:]]
        for _ in range(n-1):
            assert time.monotonic_ns()-started<600_000_000_000
            hashes.append(denied(f.call(4,ENROLL,denied_admin=True)))
        generated = invoke(OUT/'capacity/reconcile-custody',('0','-'))
        elapsed = time.monotonic_ns()-started
        signal.alarm(0)
        assert elapsed<600_000_000_000 and generated.stdout.strip()=='Ready' and int(generated.stderr.split()[-1])==costs[0]
        history = (f.root/'data/history').read_bytes()
        frames, error = history_inventory(history)
        assert error is None and [k for _,k,_,_ in frames]==[5,3]+[5]*(n-1)+[1,2]*n
        events = confirmed_events(f,genesis)
        denials = [(i,history[o:o+z]) for i,k,o,z in frames if k==5]
        assert len(events)==n and [b[-32:] for _,b in denials]==hashes
        assert all(v[6]==8 and v[56:60]==bytes.fromhex('070d0000') and v[60:92]==sha(b) for v,(_,b) in zip(events,denials))
        bindings=sorted(f.rows()[1],key=lambda r:int.from_bytes(r[1],'little'))
        assert bindings==[(STORE,LE(i),b[-32:],LE(1),LE(seq)) for seq,(i,b) in enumerate(denials,1)]
        baseline = f.verify()
        assert baseline[3:5]==(b'',tip) and f.rows()[2]==[(STORE,LE(denials[-1][0]))]
        assert invoke(OUT/'reconcile/replay-noop').stdout=='Journal Ready OutstandingReceipts 0\n'
        fd=os.pidfd_open(f.custodian_pid)
        try:
            poll=select.poll()
            poll.register(fd,select.POLLIN)
            signal.pidfd_send_signal(fd,signal.SIGTERM)
            assert poll.poll(5000)
        finally:
            os.close(fd)
        with service(f.root,f.root/'custodian',f.custodian,f.runtime,f.operator):
            assert f.verify()==baseline and invoke(OUT/'reconcile/replay-noop').stdout=='Journal Ready OutstandingReceipts 0\n'
        log=f.root/'measurement.log'
        binary=shutil.copy2(OUT/'capacity/custodian-cold',f.root/'custodian-cold')
        begin=time.monotonic_ns()
        with service(f.root,binary,f.custodian,f.runtime,f.operator,stderr_path=log), log.open() as stream:
            assert f.verify()==baseline
            first_verify=time.monotonic_ns()-begin
            tag,actual,internal_ns=stream.readline().split()
            assert tag=='COLD' and int(actual)==tip and 0<int(internal_ns)<60_000_000_000
            def server_rows():
                return [[int(v) for v in l.split()[1:]] for l in stream.readlines()]
            verify=server_rows()
            assert verify==[[3,tip,1,1]]
            scans = []
            for name,tag,cost in [('reconcile-custody','CAP',costs[1]),('replay-noop','REPLAY',costs[2])]:
                p=invoke(OUT/'capacity'/name,('0','-') if tag=='CAP' else ())
                assert p.stdout.strip()==('Ready' if tag=='CAP' else 'Journal Ready OutstandingReceipts 0')
                label,*values=p.stderr.split()
                client=list(map(int,values))
                server=server_rows()
                assert label==tag and client[-2:]==[exchange,cost]
                assert server==[[3,tip,i,1] for i,_ in denials]+[[3,tip,tip,0]]
                assert client[:-2]==([n,n,n,0,0] if tag=='CAP' else [n,2*n,n,n,n])
                scans.append(dict(client=client,server=server,actual=sum(client[:-2])+sum(sum(row[1:]) for row in server),debits=cost))
            live=invoke(OUT/'capacity/replay-live')
            assert 'LIVE_EMPTY' in live.stderr.splitlines() and live.stdout=='Journal Ready OutstandingReceipts 0\n'
            assert f.verify()==baseline and (f.root/'data/history').read_bytes()==history
    return dict(rep=rep,frames=tip,events=n,generation_ns=elapsed,generation_debits=costs[0],verify=verify,
                startup_actual=int(actual),startup_debits=None,recovery_ns=int(internal_ns),first_verify_ns=first_verify,
                reconcile=scans[0],replay=scans[1],projection=[],source=subprocess.check_output(['git','-c',f'safe.directory={Path.cwd()}','rev-parse','HEAD'],text=True).strip(),history_sha256=sha(history).hex(),kernel=os.uname().release)


if __name__=='__main__':
    assert os.getuid()==0 and limits('self')==(256*1024*1024,0)
    def expired(*_): raise TimeoutError('generation reached 600 seconds')
    signal.signal(signal.SIGALRM,expired)
    with (OUT/'cold-capacity.jsonl').open('w') as out:
        n=3333
        emit(feasibility_frames=1+3*n,import_debits=predict(n),replay_debits=(n+1)*(2*(1+3*n)+1)+3*n,generated=False)
        for n,rep in [(1,0),(33,1),(33,2),(33,3),(50,1)]:
            row=sample(n,rep)
            out.write(json.dumps(row,sort_keys=True)+'\n')
            out.flush()
            emit(frames=row['frames'],rep=rep,recovery_ns=row['recovery_ns'],replay_debits=row['replay']['debits'])
