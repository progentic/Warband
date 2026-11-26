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
    (meter/'meter.odin').write_text('package meter\nhistory, selection, embedded, consume, exchange, debits, evaluator: u64\nstage: int\nrendezvous, empty_view: bool\nrows: [4]u64\n')

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
    inject('src/runtime/reconcile_linux.odin',[('frame := frame','m.consume += 1\n\tframe := frame'),
           ('req, decode_err :=','if client.BOUNDARY { fmt.eprintln("ARCHIVE") }\n\t\treq, decode_err :=')],True)
    inject('src/store/import_linux.odin',[('b := column(stmt,0)','m.rows[m.stage] += 1\n\tb := column(stmt,0)'),
           ('row, found := event_row','m.stage = 0\n\t\trow, found := event_row'),
           ('parent, resolved := event_row','m.stage = 3\n\t\t\tparent, resolved := event_row'),
           ('last, ok := event_row','m.stage = 1\n\t\tlast, ok := event_row')])
    inject('src/store/append_linux.odin',[('row, ok := event_row','m.stage = 2\n\trow, ok := event_row')])
    inject('src/runtime/client/client_linux.odin',[('n := wb_exchange','if m.rendezvous { fmt.eprintln("EXCHANGE_BEGIN",start); m.rendezvous = false }\n\twhen BOUNDARY { fmt.eprintln("SEND",u8(req.operation)) }\n\tn := wb_exchange'),
           ('within_budget :: proc', 'BOUNDARY :: #config(WARBAND_DEBIT_TRACE,false)\nwithin_budget :: proc'),
           ('visits: u64 = 0)', 'visits: u64 = 0, site := #caller_location)'),
           ('now := wb_elapsed_ms()\n\tif now < s.deadline', '''now := wb_elapsed_ms()
    before := s.visits
    defer if BOUNDARY && visits>0 {
        fmt.eprintln("DEBIT",site.procedure,before,visits,s.visits,s.exhausted,now-(s.deadline-60_000))
    }
    if now < s.deadline'''),
           ('s.visits += visits','s.visits += visits\n\tm.debits += visits'),('return reply, within_budget(s,2*reply.tip+1)',
           'before := s.visits\n\tok := within_budget(s,2*reply.tip+1)\n\tm.exchange += s.visits-before\n\treturn reply,ok')],True)
    inject('cmd/reconcile-custody/main_linux.odin',[('import "core:mem"', 'import "core:mem"\nimport wire "../../src/custody"'),
           ('if ref.sequence != 0','''fmt.eprintln("CAP",m.embedded,m.consume,m.rows[0],m.rows[1],m.rows[2],m.exchange,session.visits)
    if c.BOUNDARY {
        fmt.eprintln("END",result,session.visits,session.exhausted,c.wb_elapsed_ms()-(session.deadline-60_000))
        if !session.exhausted {
            page,ok := c.verify(&session,0)
            fmt.eprintln("OVER",ok,page.tip,session.visits,session.exhausted,m.embedded)
        }
        _,again := c.verify(&session,0)
        fmt.eprintln("LATCH",again,session.visits,session.exhausted,m.embedded)
        fresh := c.Session{path=session.path,uid=session.uid,store=session.store,epoch=session.epoch,deadline=c.wb_elapsed_ms()+60_000}
        page,ready := c.verify(&fresh,0)
        fmt.eprintln("FRESH",ready,page.tip,page.committed.sequence,string(hex.encode(page.committed.head[:])),page.pending!=nil,fresh.visits,m.embedded)
        if pledge,present := page.pending.(e.Pledge); present {
            bytes,err := wire.encode_pledge(pledge,fresh.store,fresh.epoch)
            fmt.eprintln("PLEDGE",err,string(hex.encode(bytes[:])))
        }
    }
    if ref.sequence != 0''')])
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
                        '\n\tif #config(WARBAND_COLD_PROBE,false) { fmt.eprintln("COLD",m.history,time.duration_nanoseconds(time.tick_since(cold))) }'))
        inject('src/store/replay_linux.odin',[('bytes := column(stmt,0)','m.rows[0] += 1\n\t\tbytes := column(stmt,0)'),
               ('if valid && seg.journal==cp', 'if valid && seg.journal==cp && mark_matches(&state,cp.store,seg.last_import) && h.task==nil { m.empty_view = true }\n\t\t\tif valid && seg.journal==cp')])
        inject('src/replay/prefix.odin',[('event,valid := decode','m.rows[1] += 1\n\t\tevent,valid := decode')])
        inject('src/replay/reduce.odin',[('slot := 0','m.rows[2] += 1\n\t\tslot := 0'),('used += 1','m.consume += 1\n\t\t\t\tused += 1')])
        inject('cmd/replay-noop/main_linux.odin',[('cursor,_ :=','m.consume += 1\n\t\tcursor,_ :='),
               ('fmt.println("Journal"','if m.empty_view { fmt.eprintln("LIVE_EMPTY") }\n\tfmt.eprintln("REPLAY",m.embedded,m.consume,m.rows[0],m.rows[1],m.rows[2],m.exchange,s.visits)\n\tfmt.println("Journal"')])
    odin = root/'.local/toolchains/odin-linux_amd64/odin'
    sqlite = root/'.local/dependencies/sqlite/555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76/linux_amd64'
    targets = ('custodian-cold','custodian','reconcile-custody','debit-boundary','replay-noop','replay-live') if recovery else ('custodian','reconcile-custody','noop-gate','accept-noop')
    if recovery:
        targets += ('cold-limits',)
    for cmd in targets:
        binary = dest/cmd
        if cmd=='cold-limits':
            # This target is built last. Only its disposable source copy has these observations.
            def edit(name, pairs):
                file = work/name
                source = file.read_text()
                for old,new in pairs:
                    assert source.count(old)==1, (name,old)
                    source = source.replace(old,new)
                file.write_text(source)
            # PIE relocation preserves the low six bits. Preserve the production arena's
            # base modulo the authorization map's alignment without changing usable bytes.
            symbols = subprocess.check_output(['nm','-an',out/'custodian/normal/custodian'],text=True)
            address, = [l.split()[0] for l in symbols.splitlines() if l.endswith(' main::workspace')]
            base = int(address,16)%64
            edit('cmd/custodian/main_linux.odin', [
                ('workspace: [8*1024*1024]u8','storage: [8*1024*1024+63]u8'),
                ('mem.arena_init(&arena,workspace[:])', f'''offset := (64+{base}-int(uintptr(&storage[0])%64))%64
    workspace := storage[offset:offset+8*1024*1024]
    fmt.eprintln("ARENA",uintptr(raw_data(workspace))%64,len(workspace))
    mem.arena_init(&arena,workspace)'''),
                ('main :: proc()', '''trace_alloc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old: rawptr, old_size: int, loc := #caller_location) -> ([]byte,mem.Allocator_Error) {
    arena := cast(^mem.Arena)data
    before := arena.offset
    buf,err := mem.arena_allocator_proc(data,mode,size,alignment,old,old_size,loc)
    context.allocator = context.temp_allocator
    if mode==.Alloc || mode==.Alloc_Non_Zeroed || mode==.Resize || mode==.Resize_Non_Zeroed {
        fmt.eprintln("ALLOC",loc.procedure,size,alignment,before,arena.offset,err)
    }
    return buf,err
}
main :: proc()'''),
                ('if len(args) != 5', 'if len(args) != 6'),
                ('arena: mem.Arena', 'stage,valid := strconv.parse_int(args[5]); if !valid || stage<0 || stage>5 { os.exit(2) }; m.stage=stage; arena: mem.Arena'),
                ('cold := time.tick_now()', 'context.allocator.procedure = trace_alloc\n\tcold := time.tick_now()'),
                ('a := svc.wb_listen(0)', 'fmt.eprintln("LISTEN"); a := svc.wb_listen(0)')])
            edit('src/custody/linux/service_linux.odin', [
                ('import c "../"', 'import "core:fmt"\nimport "core:time"\nimport c "../"'),
                ('if size < 0 || size > 8*1024*1024', 'fmt.eprintln("SIZE",size); if size < 0 || size > 8*1024*1024'),
                ('return data, wb_read("history", raw_data(data), uintptr(size)) == 0',
                 'rc := wb_read("history",raw_data(data),uintptr(size)); fmt.eprintln("READ",size,rc); return data,rc==0'),
                ('recover_checkpoint :: proc', '''cold_now :: proc(start: i64, site: int) -> i64 {
    if m.stage==5 && site==2 { time.sleep(60_050*time.Millisecond) }
    now := wb_millis()
    if m.stage>=1 && m.stage<=4 {
        now = start+59_999
        if m.stage==site+1 { now=start+60_000 }
    }
    fmt.eprintln("CLOCK",site,now-start)
    return now
}
recover_checkpoint :: proc'''),
                ('if present && head == nil', 'fmt.eprintln("VALID",status,view.ordinal); if present && head == nil'),
                ('elapsed := wb_millis() - start','elapsed := cold_now(start,1) - start'),
                ('now := wb_millis()\n\tif now < start','now := cold_now(start,2)\n\tif now < start'),
                ('now = wb_millis()\n\tif now < start','now = cold_now(start,3)\n\tif now < start'),
                ('if wb_sync_history(i64(end))','fmt.eprintln("TRIM",end); if wb_sync_history(i64(end))')])
            cmd='custodian'
        cold = cmd=='custodian-cold'
        if cold:
            cmd='custodian'
        lib = 'custodian/normal' if cmd=='custodian' else 'reconcile'
        extra = [] if cmd=='custodian' else [f'-collection:warband_sqlite={sqlite}']
        if cmd=='noop-gate':
            extra.append('-define:WARBAND_TEST_CLAIM_BARRIER=true')
        if cold:
            extra.append('-define:WARBAND_COLD_PROBE=true')
        if cmd=='debit-boundary':
            cmd='reconcile-custody'
            extra.append('-define:WARBAND_DEBIT_TRACE=true')
        if cmd=='replay-live':
            cmd='replay-noop'
            extra.append('-define:WARBAND_REPLAY_LIVE_COMPARE=true')
        subprocess.run([odin,'build',work/'cmd'/cmd,'-target:linux_amd64','-vet','-warnings-as-errors',
                        f'-extra-linker-flags:-L{out/lib}',f'-out:{binary}',*extra],check=True)
        print(binary, hashlib.sha256(binary.read_bytes()).hexdigest())
