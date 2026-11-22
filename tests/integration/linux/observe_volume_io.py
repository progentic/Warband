"""Read-only observers for the production x86-64 qualification binaries."""
import contextlib
import re
import shutil
import subprocess
import time
from pathlib import Path


@contextlib.contextmanager
def sqlite_steps(binary, log):
    # Verify the accessor loads in this exact pinned, optimized binary before
    # reading Vdbe.db, Vdbe.zSql and the connection error fields at return.
    try:
        for symbol, loads in [('sqlite3_db_handle',['(%rdi),%rax']), ('sqlite3_sql',['0xf8(%rdi),%rax']),
                              ('sqlite3_extended_errcode',['0x67(%rdi)','0x50(%rdi),%ebx'])]:
            dis = subprocess.check_output(['objdump','-d','--disassemble='+symbol,binary],text=True)
            if not all(load in dis for load in loads):
                raise ValueError('unsupported accessor layout: '+symbol)
        if not shutil.which('bpftrace'):
            raise ValueError('bpftrace unavailable')
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        log.write_text(str(error))
        yield False
        return
    script = f'''
uprobe:{binary}:sqlite3_step {{ @stmt[tid] = arg0; }}
uretprobe:{binary}:sqlite3_step /@stmt[tid]/ {{
  $s = @stmt[tid]; $db = *uptr((uint64*)$s); $sql = *uptr((uint64*)($s+248));
  $err = *uptr((uint8*)($db+103)) ? 7 : *uptr((int32*)($db+80));
  printf("step %d %d %s\\n",(int32)retval,$err,str(uptr((uint8*)$sql)));
  delete(@stmt[tid]);
}}
BEGIN {{ printf("attached\\n"); }}
'''
    with log.open('w') as out, subprocess.Popen(['bpftrace','-q','-B','line','-e',script],
                                                 stdout=out,stderr=subprocess.STDOUT) as p:
        try:
            until = time.monotonic()+12
            while 'attached\n' not in log.read_text() and p.poll() is None and time.monotonic()<until:
                time.sleep(.05)
            yield p.poll() is None and 'attached\n' in log.read_text()
        finally:
            if p.poll() is None:
                p.send_signal(2)
            p.wait(timeout=10)


@contextlib.contextmanager
def custody_calls(pid, log):
    with subprocess.Popen(['strace','-qq','-ttt','-yy','-xx','-s','256','-e','trace=write,fsync,fdatasync',
                           '-p',str(pid),'-o',log],stderr=subprocess.PIPE) as p:
        try:
            until=time.monotonic()+5
            while int(re.search(r'TracerPid:\s+(\d+)',Path(f'/proc/{pid}/status').read_text())[1])!=p.pid:
                assert p.poll() is None and time.monotonic()<until, 'custodian tracer unavailable'
                time.sleep(.02)
            yield
        finally:
            if p.poll() is None:
                p.send_signal(2)
            p.wait(timeout=10)


def traced_import(f, store, log):
    args = ['strace','-f','-qq','-yy','-ttt','-s','0','-e',
            'trace=write,pwrite64,ftruncate,fallocate,fsync,fdatasync','-o',log,'setpriv',
            f'--reuid={f.runtime}',f'--regid={f.runtime}','--clear-groups','--no-new-privs',
            f.root/'importer',f.db,f.root/'endpoints/runtime.sock',str(f.custodian),store.hex(),'1','0','-']
    return subprocess.run(args,capture_output=True,text=True,timeout=70)
