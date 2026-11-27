"""Run the installed normal issuer and transport in a private mount and network namespace."""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

import test_provider_transport as tls_fixture
from test_marker_approval import cli
from test_model_request import actor, command, request_store
from test_provider_connector import DNS, STUB
from test_receipt_import import OUT
from test_workflow_admission import check_admission, line, replay


class HeldEndpoint(tls_fixture.Endpoint):
    def do_POST(self):
        self.server.entered.set()
        if not self.server.release.wait(8):
            raise TimeoutError('handoff inspection barrier')
        super().do_POST()


@contextlib.contextmanager
def started(install, f):
    supply, child = socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
    with supply, child:
        proc = subprocess.Popen([sys.executable,'-I',install/'provider_handoff.py','--provision',
                                 f.root,'abc',str(child.fileno())], cwd='/', env={}, pass_fds=(child.fileno(),),
                                stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
        child.close()
        supply.settimeout(12)
        try:
            yield proc, supply
        finally:
            if proc.poll() is None: proc.kill()
            proc.wait(timeout=8)
            proc.stdout.close()
            proc.stderr.close()


def fd_targets(pid):
    fds = Path(f'/proc/{pid}/fd')
    return {int(p.name):os.readlink(p) for p in fds.iterdir()}


def children(pid):
    return [int(n) for n in Path(f'/proc/{pid}/task/{pid}/children').read_text().split()]


def check_failed_issuance(f,install,genesis,fact):
    assert replay(f,genesis,[18])==[fact] and not f.query('SELECT request_id FROM consumed_requests')
    assert not list((f.root/'attempts').iterdir())
    with started(install,f) as (restart, other):
        assert restart.wait(timeout=8)!=0 and other.recv(2)==b''
    assert replay(f,genesis,[18])==[fact]
    command(f,'recover',['Expired','Ready'])
    replay(f,genesis,[18,19])


def colliding_custodian(f, install):
    anchor=f.root/'intake.anchor'
    saved=anchor.read_bytes()
    a,b=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
    with a,b:
        try:
            anchor.write_bytes(saved[:64]+struct.pack('<I',60004))
            rejected=subprocess.run([sys.executable,'-I',install/'provider_handoff.py','--setup',f.root,'abc',str(b.fileno())],
                                    pass_fds=(b.fileno(),),capture_output=True,timeout=8)
            b.close()
            assert rejected.returncode==1 and a.recv(9)==b''  # no child registration
        finally:
            anchor.write_bytes(saved)


def inspect_provider_fds(f, issuer, courier, launcher, provisioner, roles):
    authority = {v for v in fd_targets(issuer).values() if str(f.root) in v}
    assert any('/journal' in v for v in authority)
    for record in Path('/proc/net/unix').read_text().splitlines()[1:]:
        fields = record.split()
        if len(fields)>7 and (str(f.root) in fields[7] or 'warband.approval.' in fields[7]):
            authority.add(f'socket:[{fields[6]}]')
    for pid in (provisioner,courier,launcher,*roles.values()):
        targets = set(fd_targets(pid).values())
        assert not authority.intersection(targets) and not any(str(f.root) in v for v in targets)
    assert fd_targets(courier)==dict.fromkeys((0,1,2),'/dev/null')
    for pid in (issuer,courier,roles[60002],roles[60003]):
        assert not any('memfd:' in v for v in fd_targets(pid).values())


def run_case(install, tls, dns, ca, case):
    with request_store() as f:
        command(f,'provision',['Ready'])
        genesis=f.verify()[2][32:]
        # A socketpair created by the runtime itself cannot impersonate the trusted setup.
        with contextlib.ExitStack() as stack:
            rd, wr=os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
            stack.callback(os.close,rd); stack.callback(os.close,wr)
            def unauthenticated():
                a,b=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
                with a,b:
                    return subprocess.run(['./model-request','handoff-abc'],cwd=f.root,pass_fds=(a.fileno(),wr),
                        env={'WB_ISSUER_FD':str(a.fileno()),'WB_OPPORTUNITY_FD':str(wr)},capture_output=True).returncode
            from test_custody_denial import as_user
            assert as_user(f.runtime,lambda: bytes([unauthenticated()]))==b'\1'
        if case=='no-credential': colliding_custodian(f,install)
        replay(f,genesis,[])
        shutil.copy2(OUT/'reconcile/marker-approval',f.root/'review')
        endpoint=tls_fixture.Observer(tls_fixture.TARGET,HeldEndpoint)
        endpoint.tls,endpoint.case=tls,'untrusted' if case=='system-roots' else 'lost-reply' if 'death' in case else 'success'
        endpoint.entered=threading.Event()
        endpoint.token=secrets.token_hex(24)
        dns.queries=[]; dns.case='control'; dns.hold=True; dns.release.clear()
        sni=[]
        tls.set_servername_callback(lambda sock,name,ctx:sni.append(name))
        with tls_fixture.observing(endpoint), started(install,f) as (proc,source):
            assert source.recv(2)==b'K'
            courier,=children(proc.pid)
            siblings=children(courier)
            assert len(siblings)==2
            issuer,= [p for p in siblings if Path(f'/proc/{p}/exe').resolve().name=='model-request']
            launcher,=set(siblings)-{issuer}
            assert Path(f'/proc/{launcher}/exe').resolve()==install/'transport-normal'
            status=dict(l.split(':',1) for l in Path(f'/proc/{courier}/status').read_text().splitlines())
            assert status['Uid'].split()==['60004']*4 and status['NoNewPrivs'].strip()=='1'
            assert all(int(status[k],16)==0 for k in ('CapEff','CapPrm','CapInh','CapAmb'))
            assert fd_targets(courier)==dict.fromkeys((0,1,2),'/dev/null')
            assert Path(f'/proc/{courier}/cwd').resolve()==Path('/')
            fact,=replay(f,genesis,[18])
            rid=fact[56:72]
            deadline=int.from_bytes(fact[152:160],'little')
            body=tls_fixture.fixture_body(rid.hex().encode())
            endpoint.expected_size=len(body); endpoint.expected_body=body
            endpoint.expected_digest=hashlib.sha256(body).hexdigest()
            content=json.dumps(dict(schema_version=1,request_id=rid.hex(),action='create_marker',
                                    expected_effect='marker_contains_payload',payload_b64='YWJj'))
            endpoint.reply=json.dumps(dict(object='chat.completion', model=tls_fixture.MODEL,
                choices=[dict(index=0,finish_reason='stop',message=dict(role='assistant',content=content))])).encode()
            assert not dns.queries and not endpoint.connections
            with started(install,f) as (duplicate, other):
                assert duplicate.wait(timeout=8)!=0 and other.recv(2)==b''
            assert not dns.queries and replay(f,genesis,[18])==[fact]
            if case=='no-credential':
                source.sendall(b'N')
                out,err=proc.communicate(timeout=8)
                assert proc.returncode!=0 and not err and out.strip()==b'ProviderFailure CredentialUnavailable CountsUnavailable'
                check_failed_issuance(f,install,genesis,fact)
                assert not dns.queries and endpoint.connections==endpoint.requests==0
                print(json.dumps(dict(case=case,terminal=out.decode().strip(),connections=0,requests=0,
                                      admissions=0,permits=0,custodian_collision='refused before child registration')),flush=True)
                return
            with os.fdopen(os.memfd_create('synthetic-warband-token',os.MFD_ALLOW_SEALING),'w+b') as token:
                token.write(endpoint.token.encode()); token.flush()
                fcntl.fcntl(token,fcntl.F_ADD_SEALS,fcntl.F_SEAL_SEAL|fcntl.F_SEAL_GROW|fcntl.F_SEAL_SHRINK|fcntl.F_SEAL_WRITE)
                socket.send_fds(source,[b'K'],[token.fileno()])
            until=time.monotonic()+4
            while not dns.queries and time.monotonic()<until: time.sleep(.005)
            assert dns.queries==[1]
            roles={Path(f'/proc/{p}').stat().st_uid:p for p in children(launcher)}
            assert set(roles)=={60001,60002,60003}
            inspect_provider_fds(f,issuer,courier,launcher,proc.pid,roles)
            dns.release.set()
            if case!='system-roots':
                assert endpoint.entered.wait(8)
                if case.endswith('-death'):
                    os.kill(issuer if case=='issuer-death' else courier,signal.SIGKILL)
                endpoint.release.set()
            binding=None
            if case=='approve':
                assert line(proc)=='Admitted' and line(proc)=='AwaitingOperator'
                binding=check_admission(f,genesis,rid,b'abc',2,deadline)
                wire=replay(f,genesis,[18,1,11])[-1]
                assert cli(f,wire,b'approve',payload=b'abc')[0]==0
                terminal=line(proc)
                assert terminal=='Permitted' and proc.wait(timeout=6)==0
                settled=replay(f,genesis,[18,1,11,12,13])
                with started(install,f) as (restart, other):
                    assert restart.wait(timeout=8)!=0 and other.recv(2)==b''
                assert replay(f,genesis,[18,1,11,12,13])==settled
            else:
                out,err=proc.communicate(timeout=12)
                assert proc.returncode!=0 and not err and endpoint.token.encode() not in out
                terminal=out.decode().strip() if case=='system-roots' else 'No issuer result'
                if case=='system-roots':
                    assert out.strip()==b'ProviderFailure TlsFailure Observed 0 0 0 0' and endpoint.unknown_ca_alert
                check_failed_issuance(f,install,genesis,fact)
        until=time.monotonic()+4
        for pid in [courier,issuer,launcher,*roles.values()]:
            while Path(f'/proc/{pid}').exists() and time.monotonic()<until: time.sleep(.01)
            assert not Path(f'/proc/{pid}').exists()
        assert dns.queries==[1,28,1,28] and sni==[tls_fixture.HOST]
        assert endpoint.valid and endpoint.connections==1 and endpoint.requests==int(case!='system-roots')
        if case!='system-roots': assert endpoint.exact_body
        print(json.dumps(dict(case=case,terminal=terminal,proposal_binding=binding,requests=endpoint.requests,connections=endpoint.connections,
              trust='system' if case=='system-roots' else 'private mount: synthetic CA',
              ca_bundle_sha256=hashlib.sha256(Path('/etc/ssl/certs/ca-certificates.crt').read_bytes()).hexdigest(),
              ca_directory='/etc/ssl/certs', synthetic_leaf_sha256=ca,
              admissions=int(case=='approve'),permits=int(case=='approve'),competing_requests=0,roles_checked=sorted(roles),courier_fds=[0,1,2],descendants_reaped=True)),flush=True)


def main(install):
    if not __debug__: raise RuntimeError('qualification requires assertions')
    assert os.geteuid()==0 and os.uname().release=='6.8.0-142-generic'
    for ns in ('net','mnt'): assert os.stat('/proc/self/ns/'+ns).st_ino!=os.stat('/proc/1/ns/'+ns).st_ino
    assert socket.if_nameindex()==[(1,'lo')]
    subprocess.run(['mount','--make-rprivate','/'],check=True)
    subprocess.run(['ip','link','set','lo','up'],check=True)
    subprocess.run(['ip','addr','add',tls_fixture.TARGET[0]+'/32','dev','lo'],check=True)
    with tempfile.TemporaryDirectory() as tmp, tls_fixture.observing(tls_fixture.Observer(STUB,DNS)) as dns:
        dns.hold=False
        tls,cert,_=tls_fixture.fixture_tls(Path(tmp))
        ca=hashlib.sha256(cert.read_bytes()).hexdigest()
        run_case(install,tls,dns,ca,'no-credential')
        run_case(install,tls,dns,ca,'system-roots')
        bundle='/etc/ssl/certs/ca-certificates.crt'
        subprocess.run(['mount','--bind',cert,bundle],check=True)
        try:
            assert hashlib.sha256(Path(bundle).read_bytes()).hexdigest()==ca
            for case in ('approve','issuer-death','courier-death'): run_case(install,tls,dns,ca,case)
        finally:
            subprocess.run(['umount',bundle],check=True)


if __name__=='__main__':
    main(Path(sys.argv[1]).resolve(strict=True))
