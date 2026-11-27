#!/usr/bin/python3 -I
"""One trusted setup, followed by a credential provisioner and a wait-only courier."""
import ctypes
import fcntl
import os
from pathlib import Path
import signal
import socket
import stat
import struct
import subprocess
import sys

LIBC = ctypes.CDLL(None, use_errno=True)
COURIER_UID = 60004
PAIR = (socket.AF_UNIX, socket.SOCK_SEQPACKET)


def require(condition):
    if not condition:
        raise RuntimeError('handoff unavailable')


def prctl(op, value):
    require(LIBC.prctl(op, value, 0, 0, 0) == 0)


def parent_watch(pid):
    prctl(1, signal.SIGKILL)
    require(os.getppid() == pid)


def keep_only(fds):
    low = 3
    for fd in sorted(fds):
        require(fd >= low)
        if low < fd:
            require(LIBC.close_range(low, fd-1, 0) == 0)
        low = fd+1
    require(LIBC.close_range(low, ctypes.c_uint(-1), 0) == 0)


def drop(uid):
    os.setgroups([])
    os.setresgid(uid, uid, uid)
    os.setresuid(uid, uid, uid)
    prctl(38, 1)  # no_new_privs
    prctl(4, 0)   # nondumpable after UID change
    status = dict(line.split(':',1) for line in Path('/proc/self/status').read_text().splitlines() if ':' in line)
    require(all(int(status[name],16)==0 for name in ('CapInh','CapPrm','CapEff','CapAmb')))


def protected(path, directory=False):
    for item in (path, *path.parents):
        st = item.lstat()
        require(st.st_uid == 0 and not st.st_mode & 0o022)
        require(stat.S_ISDIR(st.st_mode) if directory or item != path else
                stat.S_ISREG(st.st_mode) and not st.st_mode & 0o6000)


def start_child(binary, args, env_fds, gate, uid, cwd):
    parent = os.getpid()
    pid = os.fork()
    if pid:
        return pid
    try:
        keep_only([gate, *env_fds.values()])
        if uid:
            drop(uid)
        parent_watch(parent)
        require(os.read(gate, 1) == b'G')
        os.close(gate)
        os.chdir(cwd)
        for fd in env_fds.values():
            os.set_inheritable(fd, True)
        os.execve(binary, [binary.name, *args], {name:str(fd) for name,fd in env_fds.items()})
    finally:
        os._exit(1)


def setup(install, store, intent, mailbox):
    # Trusted initialization finishes before either executable can issue or provision.
    protected(store, directory=True)
    roles = store/'approval.ids'
    protected(roles)
    require(roles.stat().st_size==8 and roles.stat().st_nlink==1)
    runtime, operator = struct.unpack('<II', roles.read_bytes())
    anchor = store/'intake.anchor'
    protected(anchor)
    require(anchor.stat().st_size==68 and anchor.stat().st_nlink==1)
    custodian, = struct.unpack_from('<I',anchor.read_bytes(),64)
    authority = {runtime,operator,custodian}
    require(len(authority)==3 and 0 not in authority and not authority.intersection(range(60001,60005)))
    for name in ('model-request','transport-normal'):
        protected(install/name)
    parent = os.getppid()
    require(struct.unpack('3i',mailbox.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))[:2] == (parent,0))
    left, right = socket.socketpair(*PAIR)
    grant, writer = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
    gate, release = os.pipe()
    transport = start_child(install/'transport-normal', [], dict(WB_ISSUER_FD=left.fileno(),
                            WB_OPPORTUNITY_FD=grant, WB_PROVISION_FD=mailbox.fileno()), gate, 0, '/')
    issuer = start_child(install/'model-request', ['handoff-'+intent], dict(WB_ISSUER_FD=right.fileno(),
                         WB_OPPORTUNITY_FD=writer), gate, runtime, store)
    left.close()
    right.close()
    mailbox.sendall(struct.pack('<II', transport, issuer))
    mailbox.close()
    keep_only([release])
    null = os.open('/dev/null',os.O_RDWR)
    for fd in (0,1,2):
        os.dup2(null,fd)
    os.close(null)
    drop(COURIER_UID)
    parent_watch(parent)
    require(os.write(release,b'GG')==2)
    os.close(release)
    # End either sibling's outstanding work when its peer exits unsuccessfully.
    first, status = os.wait()
    if status: return 1
    _, status = os.waitpid(transport if first==issuer else issuer, 0)
    return int(status!=0)


def provision(script, store, intent, source):
    # The credential source releases its sealed memfd on K. No credential is received
    # before all forks/execs and the permanent transition to the wait-only UID.
    require(source.family==socket.AF_UNIX and source.type==socket.SOCK_SEQPACKET and
            struct.unpack('3i',source.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))[:2]==(os.getppid(),0))
    parent, child = socket.socketpair(*PAIR)
    with parent, child:
        proc = subprocess.Popen([sys.executable,'-I',script,'--setup',store,intent,str(child.fileno())],
                                pass_fds=(child.fileno(),), stdin=subprocess.DEVNULL, cwd='/', env={})
        child.close()
        try:
            parent.settimeout(35)
            transport, _ = struct.unpack('<II',parent.recv(9))
            msg, fds, flags, _ = socket.recv_fds(parent, 2, 1)
            require(msg==b'K' and len(fds)==1 and not flags)
            with socket.socket(fileno=fds[0]) as private:
                # This pair is created by the running launcher *after* the courier's drop.
                peer = struct.unpack('3i',private.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))
                require(private.family==socket.AF_UNIX and private.type==socket.SOCK_SEQPACKET and peer[:2]==(transport,0))
                try:
                    source.settimeout(4)
                    source.sendall(b'K')
                    tag, tokens, flags, _ = socket.recv_fds(source, 2, 1)
                    try:
                        require(tag==b'K' and len(tokens)==1 and not flags)
                        secret, = tokens
                        seals = fcntl.F_SEAL_SEAL | fcntl.F_SEAL_WRITE | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SHRINK
                        require(fcntl.fcntl(secret, fcntl.F_GET_SEALS) & seals == seals)
                        require(socket.send_fds(private,[b'K'],[secret])==1)
                    finally:
                        for token in tokens: os.close(token)
                except (OSError, RuntimeError):
                    # Closing the private pair tells the launcher provisioning failed.
                    # Let it deliver the disposition to the live issuer before reaping.
                    pass
                source.close()
            return proc.wait(timeout=185)
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.wait()


def main():
    require(os.getuid()==os.geteuid()==0 and sys.flags.isolated)
    require(len(sys.argv)==5 and sys.argv[3] in ('empty','abc'))
    script = Path(__file__).absolute()
    protected(script)
    store = Path(sys.argv[2])
    require(store.is_absolute() and '..' not in store.parts)
    os.chdir('/')
    prctl(4, 0)
    fd = int(sys.argv[4])
    require(fd>=3)
    keep_only([fd])
    if sys.argv[1]=='--setup':
        return setup(script.parent,store,sys.argv[3],socket.socket(fileno=fd))
    require(sys.argv[1]=='--provision')
    parent_watch(os.getppid())
    return provision(script,store,sys.argv[3],socket.socket(fileno=fd))


if __name__=='__main__':
    try:
        code = main()
    except (OSError, ValueError, RuntimeError, struct.error, subprocess.TimeoutExpired):
        code = 1
    sys.exit(code)
