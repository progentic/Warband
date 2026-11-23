"""Check both sides of the runtime session limit with genuine receipt imports."""
import json
import shutil
import struct
import subprocess
import time

from test_custody_denial import STORE, ZERO, denied, emit, sha
from test_noop_gate import confirmed_events, history_inventory, linked_head
from test_receipt_import import ENROLL, LE, OUT, fixture


def baseline(case):
    with fixture() as (f, genesis, _):
        def generate(count):
            for _ in range(count):
                denied(f.call(4, ENROLL, denied_admin=True))
        generate(6 if case == 'D1' else 74)
        f.run('Ready')
        archives = []
        if case == 'D1':
            assert len(confirmed_events(f, genesis)) == 7
            old = f.verify()[2]
            auth, reason = bytes([91])*16, struct.pack('<H', 6)+b'review'
            genesis = sha(b'warband.epoch.v1\0'+old+LE(2)+auth+reason+ZERO)
            payload = old+LE(2)+LE(0)+genesis+auth+reason+ZERO
            assert f.call(5, payload)[0] == 0
            archives = [f.db.name, (b'WBCR'+struct.pack('<HBI',1,5,len(payload))+payload).hex()]
            f.archives = [f.db, archives[1]]
            f.epoch, f.db = 2, f.db.with_name('epoch2.db')
            f.provision()
            generate(24)
            f.run('Ready')
        generate(64 if case == 'D1' else 41)
        assert f.verify()[4] == (159 if case == 'D1' else 267)
        files = {str(p.relative_to(f.root)):p.read_bytes() for d in ('data','journal') for p in (f.root/d).iterdir()}
        return files, archives, genesis


def ledger(d1):
    tip, prior, active = (159,31,24) if d1 else (267,75,75)
    yield 'exchange', 2*tip+1
    if d1:
        yield 'reconcile_history', 1
        yield 'inspect_segment', 7
    yield 'inspect_segment', active
    for _ in range(prior):
        yield 'exchange', 2*tip+1
    for j in range(1, 65 if d1 else 33):
        yield 'exchange', 2*(tip+1)+1
        yield 'append_pledged', active+j
        yield 'confirm_stored', 1
        if not d1 and j == 32:
            return
        tip += 2
        yield 'exchange', 2*tip+1
        yield 'exchange', 2*tip+1


def check_trace(lines, server, d1, checkpoint, pending):
    tip, result = (287,'Ready') if d1 else (330,'RecoveryLimitExceeded')
    end = next(i for i,l in enumerate(lines) if l.startswith('END '))
    stage = [l.split() for l in lines[:end]]
    debits = [r[1:] for r in stage if r[0]=='DEBIT']
    total = 0
    for (site, amount), row in zip(ledger(d1), debits, strict=True):
        refused = total+amount > 100_000
        after = total if refused else total+amount
        assert row[:5] == [site,str(total),str(amount),str(after),str(refused).lower()], row
        assert 0 <= int(row[5]) < 60_000
        total = after
    meter = list(map(int,stage[-1][1:]))
    assert stage[-1][0]=='CAP' and meter[-2:]==[96_288 if d1 else 96_966,100_000]
    assert lines[end].split()[:4]==['END',result,'100000',str(not d1).lower()]
    assert 0 <= int(lines[end].split()[-1]) < 60_000
    ops = [int(r[1]) for r in stage if r[0]=='SEND']
    assert ops == [3]*(32 if d1 else 76)+[1,2,3]*(64 if d1 else 31)+([] if d1 else [1])
    assert [r[0] for r in server]==ops+[3]*(2 if d1 else 1)
    diagnostics = lines[end+1:]
    if d1:
        send, debit, over = diagnostics[:3]
        assert send=='SEND 3' and debit.split()[:6]==['DEBIT','exchange','100000','575','100000','true']
        assert 0<=int(debit.split()[-1])<60_000 and over==f'OVER false 287 100000 true {meter[0]+1}'
        diagnostics = diagnostics[3:]
    if pending:
        assert diagnostics[-1]=='PLEDGE None '+pending.hex()
        diagnostics = diagnostics[:-1]
    embedded = meter[0]+int(d1)
    latch, send, debit, fresh = diagnostics
    assert (latch,send)==(f'LATCH false 100000 true {embedded}','SEND 3')
    charge = str(2*tip+1)
    assert debit.split()[:6]==['DEBIT','exchange','0',charge,charge,'false']
    assert fresh.split()==['FRESH','true',str(tip),str(88 if d1 else 106),checkpoint[32:].hex(),str(not d1).lower(),charge,str(embedded+1)]
    assert stage.count(['ARCHIVE'])==int(d1) and all(r[1:]==[tip,1,1] for r in server[len(ops):])
    return dict(reconciliation=sum(meter[:-2])+sum(sum(r[1:]) for r in server[:len(ops)])+stage.count(['ARCHIVE']),
                diagnostics=[sum(r[1:])+1 for r in server[len(ops):]], latched_retry=0)


def boundary(case):
    start = time.monotonic_ns()
    files, archives, genesis = baseline(case)
    generation_ns = time.monotonic_ns()-start
    d1 = case=='D1'
    for measured in (False,True):
        with fixture(seed_files=files, measure=measured) as (f, _, _):
            if d1:
                f.epoch, f.db = 2, f.db.with_name('epoch2.db')
                f.archives = [f.db.with_name(archives[0]),archives[1]]
            log = f.root/'capacity.log'
            before = log.stat().st_size if measured else 0
            importer = shutil.copy2(OUT/'capacity/debit-boundary',f.root/'metered-importer') if measured else f.root/'importer'
            args = [importer,f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),str(f.epoch),'0','-',*f.archives]
            started = time.monotonic_ns()
            p = subprocess.run(args,user=f.runtime,group=f.runtime,extra_groups=[],capture_output=True,text=True,timeout=65)
            duration = time.monotonic_ns()-started
            (OUT/f'{case}-{importer.name}.log').write_text(p.stdout+p.stderr)
            calls = log.read_bytes()[before:].decode().splitlines() if measured else []
            cp, pending, tip = f.verify()[2:5]
            history = (f.root/'data/history').read_bytes()
            frames, error = history_inventory(history)
            assert error is None and tip==len(frames)==(287 if d1 else 330)
            receipts = [history[o:o+n] for _,k,o,n in frames if k==5][7 if d1 else 0:]
            events, bindings, watermark = f.rows()
            events.sort(key=lambda r:int.from_bytes(r[2],'little'))
            assert len(events)==len(bindings)==(88 if d1 else 107)
            head = genesis
            for seq, ((store,epoch,key,ev),frame) in enumerate(zip(events,receipts),1):
                ref = STORE+LE(f.epoch)+LE(seq)
                assert (store+epoch+key,ev[8:40],ev[6],ev[56:60],ev[60:92],ev[-32:])==(ref,ref,8,bytes.fromhex('070d0000'),sha(frame),head)
                assert (store,frame[11:19],frame[-32:],epoch,key) in bindings
                prior, head = head, linked_head(ev)
            assert watermark==[(STORE,frame[11:19])]
            assert cp==(ref+head if d1 else STORE+LE(1)+LE(106)+prior)
            assert pending==(b'' if d1 else cp+LE(107)+head+sha(b'warband.event.v1\0'+ev[:-32]))
            assert history.startswith(files['data/history']) and [k for _,k,_,_ in frames[(159 if d1 else 267):]]==[1,2]*(64 if d1 else 31)+([] if d1 else [1])
            if d1:
                assert f.archives[0].read_bytes()==files['journal/'+archives[0]]
            server = [list(map(int,l.split()[1:])) for l in calls if l.startswith('CAP ')]
            lines = p.stderr.splitlines()
            actual = check_trace(lines,server,d1,cp,pending) if measured else None
            evidence = dict(case=case,measured=measured,result=p.stdout.strip(),tip=tip,checkpoint=cp.hex(),pending=pending.hex(),
                            generation_ns=generation_ns,invocation_ns=duration,history_sha256=sha(history).hex(),actual=actual,client=lines,server=server)
            (OUT/f'{case}-{importer.name}.json').write_text(json.dumps(evidence,indent=1)+'\n')
            assert (p.returncode,p.stdout.strip())==((0,'Ready') if d1 else (1,'RecoveryLimitExceeded')), (p.stdout,p.stderr[-1000:])
            emit(case=case,measured=measured,tip=tip,actual=actual,invocation_ns=duration)
