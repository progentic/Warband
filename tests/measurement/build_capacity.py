"""Build probes in a disposable source copy. Run after the normal Linux build jobs."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[2]
out = root/'out/linux_amd64'
dest = out/'capacity'
dest.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=root/'.local') as temp:
    work = Path(temp)
    for folder in ('src','cmd'):
        shutil.copytree(root/folder,work/folder)
    meter = work/'src/capacity_meter'
    meter.mkdir()
    (meter/'meter.odin').write_text('package meter\nhistory, selection, embedded, consume, exchange, debits, evaluator: u64\nstage: int\nrendezvous: bool\nrows: [4]u64\n')

    def inject(file, changes, fmt=False):
        path = work/file
        source = path.read_text()
        at = source.index('\n',source.index('package '))
        imports = '\nimport m "' + os.path.relpath(meter,path.parent) + '"\n'
        if fmt:
            imports += 'import "core:fmt"\n'
        source = source[:at]+imports+source[at:]
        for old,new in changes:
            assert source.count(old)==1, (file,old)
            source = source.replace(old,new)
        path.write_text(source)

    inject('src/custody/history.odin',[('size := len(remaining)','m.history += 1\n\t\tsize := len(remaining)')])
    inject('src/custody/reply.odin',[('_, err := decode_record','m.embedded += 1\n\t\t_, err := decode_record')])
    inject('src/custody/linux/service_linux.odin',[('if ordinal > cursor','m.selection += 1\n\t\tif ordinal > cursor')])
    inject('cmd/custodian/main_linux.odin',[('fd := svc.wb_accept','m.history, m.selection, m.embedded = 0, 0, 0\n\tfd := svc.wb_accept'),
           ('if reply_error == .None', 'fmt.eprintln("CAP",u8(op),m.history,m.selection,m.embedded)\n\tif reply_error == .None')],True)
    inject('src/runtime/reconcile_linux.odin',[('frame := frame','m.consume += 1\n\tframe := frame')])
    inject('src/store/import_linux.odin',[('b := column(stmt,0)','m.rows[m.stage] += 1\n\tb := column(stmt,0)'),
           ('row, found := event_row','m.stage = 0\n\t\trow, found := event_row'),
           ('parent, resolved := event_row','m.stage = 3\n\t\t\tparent, resolved := event_row'),
           ('last, ok := event_row','m.stage = 1\n\t\tlast, ok := event_row')])
    inject('src/store/append_linux.odin',[('row, ok := event_row','m.stage = 2\n\trow, ok := event_row')])
    inject('src/runtime/client/client_linux.odin',[('n := wb_exchange','if m.rendezvous { fmt.eprintln("EXCHANGE_BEGIN",start); m.rendezvous = false }\n\tn := wb_exchange'),
           ('s.visits += visits','s.visits += visits\n\tm.debits += visits'),('return reply, within_budget(s,2*reply.tip+1)',
           'before := s.visits\n\tok := within_budget(s,2*reply.tip+1)\n\tm.exchange += s.visits-before\n\treturn reply,ok')],True)
    inject('cmd/reconcile-custody/main_linux.odin',[('if ref.sequence != 0','fmt.eprintln("CAP",m.embedded,m.consume,m.rows[0],m.rows[1],m.rows[2],m.exchange,session.visits)\n\tif ref.sequence != 0')])
    inject('src/runtime/noop_gate_linux.odin',[('continue // reconcile the pre-dispatch','m.rendezvous = true\n\t\t\tcontinue // reconcile the pre-dispatch')])
    inject('src/runtime/noop_evaluator_linux.odin',[('raw := h.observation_bytes','m.evaluator += 1\n\traw := h.observation_bytes')])
    for cmd,marker in [('noop-gate','fmt.println("gate_result"'),('accept-noop','if result==.Accepted')]:
        inject(f'cmd/{cmd}/main_linux.odin',[(marker,'fmt.eprintln("TASK",m.embedded,m.consume,m.rows[0],m.rows[1],m.rows[2],m.rows[3],m.evaluator,m.exchange,m.debits)\n\t'+marker)])
    recovery = '--recovery' in sys.argv[1:]
    if recovery:
        path = work/'cmd/custodian/main_linux.odin'
        text = path.read_text().replace('import "core:os"', 'import "core:os"\nimport "core:time"')
        marker = 'if !svc.recover_checkpoint(&s) { os.exit(4) }'
        assert text.count(marker)==1
        path.write_text(text.replace(marker,'cold := time.tick_now()\n\t'+marker+
                        '\n\tfmt.eprintln("COLD",m.history,time.duration_nanoseconds(time.tick_since(cold)))'))
        inject('src/store/replay_linux.odin',[('bytes := column(stmt,0)','m.rows[0] += 1\n\t\tbytes := column(stmt,0)'),
               ('if valid && seg.journal==cp', 'if valid && seg.journal==cp && mark_matches(&state,cp.store,seg.last_import) && h.task==nil { fmt.eprintln("LIVE_EMPTY") }\n\t\t\tif valid && seg.journal==cp')],True)
        inject('src/replay/prefix.odin',[('event,valid := decode','m.rows[1] += 1\n\t\tevent,valid := decode')])
        inject('src/replay/reduce.odin',[('slot := 0','m.rows[2] += 1\n\t\tslot := 0'),('used += 1','m.consume += 1\n\t\t\t\tused += 1')])
        inject('cmd/replay-noop/main_linux.odin',[('cursor,_ :=','m.consume += 1\n\t\tcursor,_ :='),
               ('fmt.println("Journal"','fmt.eprintln("REPLAY",m.embedded,m.consume,m.rows[0],m.rows[1],m.rows[2],m.exchange,s.visits)\n\tfmt.println("Journal"')])
    odin = root/'.local/toolchains/odin-linux_amd64/odin'
    sqlite = root/'.local/dependencies/sqlite/555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76/linux_amd64'
    targets = ('custodian','reconcile-custody','replay-noop','replay-live') if recovery else ('custodian','reconcile-custody','noop-gate','accept-noop')
    for cmd in targets:
        lib = 'custodian/normal' if cmd=='custodian' else 'reconcile'
        extra = [] if cmd=='custodian' else [f'-collection:warband_sqlite={sqlite}']
        if cmd=='noop-gate':
            extra.append('-define:WARBAND_TEST_CLAIM_BARRIER=true')
        binary = dest/(cmd+'-cold' if recovery and cmd=='custodian' else cmd)
        if cmd=='replay-live':
            cmd='replay-noop'
            extra.append('-define:WARBAND_REPLAY_LIVE_COMPARE=true')
        subprocess.run([odin,'build',work/'cmd'/cmd,'-target:linux_amd64','-vet','-warnings-as-errors',
                        f'-extra-linker-flags:-L{out/lib}',f'-out:{binary}',*extra],check=True)
        print(binary, hashlib.sha256(binary.read_bytes()).hexdigest())
