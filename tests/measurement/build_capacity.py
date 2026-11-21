"""Build probes in a disposable source copy. Run after the normal Linux build jobs."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

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
    (meter/'meter.odin').write_text('package meter\nhistory, selection, embedded, consume, exchange: u64\nstage: int\nrows: [3]u64\n')

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
           ('last, ok := event_row','m.stage = 1\n\t\tlast, ok := event_row')])
    inject('src/store/append_linux.odin',[('row, ok := event_row','m.stage = 2\n\trow, ok := event_row')])
    inject('src/runtime/client/client_linux.odin',[('return reply, within_budget(s,2*reply.tip+1)',
           'before := s.visits\n\tok := within_budget(s,2*reply.tip+1)\n\tm.exchange += s.visits-before\n\treturn reply,ok')])
    inject('cmd/reconcile-custody/main_linux.odin',[('if ref.sequence != 0','fmt.eprintln("CAP",m.embedded,m.consume,m.rows[0],m.rows[1],m.rows[2],m.exchange,session.visits)\n\tif ref.sequence != 0')])
    odin = root/'.local/toolchains/odin-linux_amd64/odin'
    sqlite = root/'.local/dependencies/sqlite/555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76/linux_amd64'
    for cmd,lib,extra in [('custodian','custodian/normal',[]),('reconcile-custody','reconcile',[f'-collection:warband_sqlite={sqlite}'])]:
        binary = dest/cmd
        subprocess.run([odin,'build',work/'cmd'/cmd,'-target:linux_amd64','-vet','-warnings-as-errors',
                        f'-extra-linker-flags:-L{out/lib}',f'-out:{binary}',*extra],check=True)
        print(binary, hashlib.sha256(binary.read_bytes()).hexdigest())
