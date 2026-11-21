"""Three paired Slice 5 task checkpoints. Run in the recorded disposable Linux scope."""
import contextlib
import json
import os
from pathlib import Path
import select
import shutil
import signal
import struct
import subprocess
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'integration/linux'))
from test_custody_denial import STORE, limits, sha
from test_noop_gate import confirmed_events, seed, wait_for_stop
from test_receipt_import import ENROLL, OUT, fixture

def counters(tag, data):
    marker,*values = data.split()
    assert marker==tag, data
    return list(map(int,values))

# Connected peer credentials come from the dropped-UID child. One incomplete
# bounded request keeps the denial outstanding until the gate begins its exchange.
GENERATOR = """
import os,socket,sys
wire = bytes.fromhex(sys.argv[2])
with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as sock:
    sock.settimeout(30)
    sock.connect(sys.argv[1])
    sock.sendall(wire[:-1])
    print('READY',flush=True)
    assert sys.stdin.buffer.read(1)==b'X'
    sock.sendall(wire[-1:])
    sock.shutdown(socket.SHUT_WR)
    print(sock.makefile('rb').read(491).hex())
"""

def line(stream):
    assert select.select([stream],[],[],30)[0], 'measurement rendezvous timeout'
    return stream.readline().strip()

def measure(n):
    with fixture(measure=True) as (f,genesis,_), (f.root/'capacity.log').open() as stream:
        def server():
            return [counters('CAP',line) for line in stream.readlines()]

        for cmd in ('reconcile-custody','noop-gate','accept-noop'):
            shutil.copy2(OUT/'capacity'/cmd,f.root/cmd)
        common = [f.db,f.root/'endpoints/runtime.sock',str(f.custodian),STORE.hex(),'1']
        options = dict(user=f.runtime,group=f.runtime,extra_groups=[],stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE,text=True)
        def invoke(cmd,args,expected,tag):
            p = subprocess.run([f.root/cmd,*common,*args],**options,check=True,timeout=65)
            assert p.stdout.split()[0]==expected, p.stdout
            return dict(client=counters(tag,p.stderr),server=server(),output=p.stdout.strip())

        server()  # discard fixture enrollment and its inspection
        startup = invoke('reconcile-custody',['0','-'],'Ready','CAP')
        assert startup['client']==[0,0,0,0,0,3,3] and startup['server']==[[3,1,1,0]]
        index = invoke('accept-noop',['provision-index'],'IndexVerified','TASK')
        seed(f)
        inputs = server()
        assert [(r[0],r[1]) for r in inputs]==[(1,1),(2,2),(1,3),(2,4)]
        with subprocess.Popen([f.root/'noop-gate',*common,'2'],**options) as gate:
            try:
                wait_for_stop(gate)  # same confirmed claim stop in each arm
                pre = server()
                wire = b'WBCR'+struct.pack('<HBI',1,4,len(ENROLL))+ENROLL
                with contextlib.ExitStack() as cleanup:
                    started = time.clock_gettime_ns(time.CLOCK_BOOTTIME)
                    if n:
                        worker = cleanup.enter_context(subprocess.Popen(
                            ['/usr/bin/python3','-c',GENERATOR,str(f.root/'endpoints/operator.sock'),wire.hex()],
                            stdin=subprocess.PIPE,**options))
                        cleanup.callback(lambda: worker.kill() if worker.poll() is None else None)
                        assert line(worker.stdout)=='READY'
                    gate.send_signal(signal.SIGCONT)
                    marker, exchange_ms = line(gate.stderr).split()
                    assert marker=='EXCHANGE_BEGIN'
                    if n:
                        reply_hex,err = worker.communicate('X',timeout=30)
                        reply = bytes.fromhex(reply_hex)
                        assert worker.returncode==0 and len(reply)==151 and reply[7:9]==b'\x0f\0'
                        assert reply[13:45]==sha(b'warband.request.v1\0'+wire) and any(reply[45:77])
                    ended = time.clock_gettime_ns(time.CLOCK_BOOTTIME)
                    assert started//1_000_000<=int(exchange_ms)<=ended//1_000_000
                wait_for_stop(gate)  # at primitive return, still holding the writer lock
                overlap = server()
                gate.send_signal(signal.SIGCONT)
                wait_for_stop(gate)  # confirmed observation
                gate.send_signal(signal.SIGCONT)
                output,stderr = gate.communicate(timeout=65)
            finally:
                if gate.poll() is None:
                    gate.kill()
                    gate.wait(timeout=10)
        assert gate.returncode==0 and 'gate_result Dispatched' in output and output.count('primitive_invoked')==1
        assert sum(r[0]==4 for r in overlap)==n
        gate_row = dict(client=counters('TASK',stderr),server=pre+overlap+server())
        # This read is fixture inspection. It never asks the custodian to scan.
        ev, = [ev for _,_,_,ev in f.rows()[0] if ev[6:8]==b'\x06\0']
        seq = int.from_bytes(ev[32:40],'little')
        accepted = invoke('accept-noop',[str(seq),'1','2'],'Accepted','TASK')
        rows = f.rows()
        before = f.verify()
        events = confirmed_events(f,genesis)
        assert [len(t) for t in rows]==[7+n,n,int(n>0)]
        assert sorted(int.from_bytes(e[6:8],'little') for e in events)==sorted([1,2,3,4,5,6,7]+[8]*n)
        assert len(f.query('SELECT * FROM accepted_attempts'))==1 and before[4]==1+14+3*n
        assert events[-1][56:88]==ev[8:40] and events[-1][136:161]==struct.pack('<QQQB',1,2,2,2)
        server()
        replay = invoke('accept-noop',[str(seq),'1','2'],'Recorded','TASK')
        assert f.rows()==rows and f.verify()==before
        return dict(startup=startup,index=index,inputs=inputs,gate=gate_row,accept=accepted,retry=replay,
                    overlap=overlap,generator_boottime_ns=[started,ended],exchange_ms=int(exchange_ms),confirmed=len(f.query('SELECT * FROM accepted_attempts')),
                    evaluation=ev[8:40].hex(),transition=events[-1].hex(),tip=before[4])

def actual(rows):
    return sum(sum(r[1:]) for r in rows)

def report(rows):
    assert [(r['rep'],r['denials']) for r in rows]==[(rep,n) for rep in range(1,4) for n in (0,1)]
    for r in rows:
        assert r['startup']['client']==[0,0,0,0,0,3,3] and actual(r['startup']['server'])==2
        accepted, replay = r['accept']['output'].split(), r['retry']['output'].split()
        assert accepted[0]=='Accepted' and replay[0]=='Recorded' and accepted[1:]==replay[1:]
        assert accepted[-2:]==['2','3'] and accepted[3]==str(7+r['denials'])
        assert sum(q[0]==4 for q in r['overlap'])==r['denials']
        lo,hi = r['generator_boottime_ns']
        assert lo//1_000_000<=r['exchange_ms']<=hi//1_000_000
        assert r['index']['output']=='IndexVerified' and r['startup']['output']=='Ready'
        event = bytes.fromhex(r['transition'])
        assert event[6:8]==b'\x07\0' and event[56:88].hex()==r['evaluation']
        assert event[120:136].hex()==r['accept']['output'].split()[4]
        task = actual(r['inputs'])
        charged = 0
        for phase in ('gate','accept'):
            p = r[phase]
            assert len(p['client'])==9 and p['client'][-2]<=p['client'][-1]<80000
            task += actual(p['server'])+sum(p['client'][:-2])
            charged += p['client'][-1]
        assert r['confirmed']==1 and r['tip']==15+3*r['denials'] and charged<80000
        if r['denials']==0: baseline, base_debit = task, charged
        print(f"rep={r['rep']} denials={r['denials']} actual/task={task} charged/task={charged} paired_delta={task-baseline} debit_delta={charged-base_debit} startup=2/3")

if __name__=='__main__':
    path = Path(sys.argv[1])
    if sys.argv[2:] == ['--report']:
        report([json.loads(line) for line in path.read_text().splitlines()])
    else:
        assert os.getuid()==0 and limits('self')==(256*1024*1024,0)
        with path.open('x') as out:
            for rep in range(1,4):
                for n in (0,1):
                    row = dict(rep=rep,denials=n,**measure(n))
                    print(json.dumps(row,separators=(',',':')),file=out,flush=True)
        report([json.loads(line) for line in path.read_text().splitlines()])
