"""Run the installed normal issuer and transport in a private mount and network namespace."""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import select
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


def custody_tip(f):
    _,_,checkpoint,pledge,_,_=f.verify()
    return dict(checkpoint=checkpoint.hex(),pledge=pledge.hex())


def check_observation(wire, issuance, counted):
    # Independent kind-20 representation for the two real normal-profile replies.
    assert len(wire)==156 and wire[:8]==b'WBEV'+struct.pack('<HH',2,20)
    assert wire[48:56]==struct.pack('<HHI',9,1,68)
    classification=bytes((2,2,17,1)) if counted else bytes((2,1,1,0))
    assert wire[56:124]==issuance[8:40]+issuance[56:72]+classification+bytes(16)


def check_failed_issuance(f,install,genesis,fact,case):
    observed=case in ('no-credential','system-roots')
    kinds=[18,20] if observed else [18]
    before=replay(f,genesis,kinds)
    assert before[0]==fact and not f.query('SELECT request_id FROM consumed_requests')
    if observed: check_observation(before[1],fact,case=='system-roots')
    assert f.query('SELECT wire FROM request_facts')==[(fact,)] and not list((f.root/'attempts').iterdir())
    with started(install,f) as (restart, other):
        assert restart.wait(timeout=8)!=0 and other.recv(2)==b''
    assert replay(f,genesis,kinds)==before
    command(f,'recover',['Expired','Ready'])
    events=replay(f,genesis,[*kinds,19])
    assert events[:-1]==before and events[-1][56:105]==fact[8:40]+fact[56:72]+b'\x03'
    assert f.query('SELECT wire FROM request_facts ORDER BY sequence')==[(fact,),(events[-1],)]
    command(f,'recover',['Ready'])
    assert replay(f,genesis,[*kinds,19])==events
    return [v.hex() for v in events]


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


def run_case(install, tls, dns, ca, case, prior_failure=False):
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
        prior=[]
        if prior_failure:
            with started(install,f) as (first,source):
                assert source.recv(2)==b'K'
                issuance,=replay(f,genesis,[18])
                source.sendall(b'N')
                out,err=first.communicate(timeout=8)
                assert out.strip()==b'ProviderFailure CredentialUnavailable CountsUnavailable' and not err
            check_failed_issuance(f,install,genesis,issuance,'no-credential')
            prior=[18,20,19]
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
            fact=replay(f,genesis,[*prior,18])[-1]
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
            assert not dns.queries and replay(f,genesis,[*prior,18])[-1]==fact
            if case=='no-credential':
                source.sendall(b'N')
                out,err=proc.communicate(timeout=8)
                assert proc.returncode!=0 and not err and out.strip()==b'ProviderFailure CredentialUnavailable CountsUnavailable'
                history=check_failed_issuance(f,install,genesis,fact,case)
                assert not dns.queries and endpoint.connections==endpoint.requests==0
                print(json.dumps(dict(case=case,**custody_tip(f),history=history,terminal=out.decode().strip(),connections=0,requests=0,
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
                    # Sending SIGKILL to the courier does not synchronously stop its issuer.
                    # Hold the peer reply until the kernel confirms issuer exit.
                    with contextlib.ExitStack() as barrier:
                        pidfd=os.pidfd_open(issuer)
                        barrier.callback(os.close,pidfd)
                        os.kill(issuer if case=='issuer-death' else courier,signal.SIGKILL)
                        assert select.select([pidfd],[],[],5)[0]==[pidfd]
                endpoint.release.set()
            binding=None
            history=[]
            if case=='approve':
                assert line(proc)=='Admitted' and line(proc)=='AwaitingOperator'
                binding=check_admission(f,genesis,rid,b'abc',2,deadline,prior)
                wire=replay(f,genesis,[*prior,18,1,11])[-1]
                if prior_failure:
                    # The prior observational history moves Ref.sequence but leaves T/C at 1/0.
                    with subprocess.Popen(['./review','decide'],**actor(f,f.operator),stdin=subprocess.PIPE,
                                          stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0) as operator:
                        display=[line(operator) for _ in range(6)]
                        assert display[0]==f'Proposal {wire[8:24].hex()} 1 6' and display[3].startswith('Versions 1 0 ')
                        assert display[4]==f'Fingerprint {binding[1]} Length 3 SHA256 {hashlib.sha256(b"abc").hexdigest()}'
                        out,err=operator.communicate(b'approve\n',timeout=8)
                        assert operator.returncode==0 and not err and out.strip()==f'Permitted {wire[8:24].hex()} 1 7'.encode()
                else:
                    assert cli(f,wire,b'approve',payload=b'abc')[0]==0
                terminal=line(proc)
                assert terminal=='Permitted' and proc.wait(timeout=6)==0
                settled=replay(f,genesis,[*prior,18,1,11,12,13])
                with started(install,f) as (restart, other):
                    assert restart.wait(timeout=8)!=0 and other.recv(2)==b''
                assert replay(f,genesis,[*prior,18,1,11,12,13])==settled
                assert settled[-2][56:88]==wire[8:40] and settled[-1][56:88]==settled[-2][8:40]
                history=[v.hex() for v in settled]
            else:
                out,err=proc.communicate(timeout=12)
                assert proc.returncode!=0 and not err and endpoint.token.encode() not in out
                terminal=out.decode().strip() or 'No issuer result'
                if case=='issuer-death': assert not out
                if case=='courier-death': assert out.strip() in (b'',b'OutcomeUncertain')
                if case=='system-roots':
                    assert out.strip()==b'ProviderFailure TlsFailure Observed 0 0 0 0' and endpoint.unknown_ca_alert
                history=check_failed_issuance(f,install,genesis,fact,case)
        until=time.monotonic()+4
        for pid in [courier,issuer,launcher,*roles.values()]:
            while Path(f'/proc/{pid}').exists() and time.monotonic()<until: time.sleep(.01)
            assert not Path(f'/proc/{pid}').exists()
        assert dns.queries==[1,28,1,28] and sni==[tls_fixture.HOST]
        assert endpoint.valid and endpoint.connections==1 and endpoint.requests==int(case!='system-roots')
        if case!='system-roots': assert endpoint.exact_body
        print(json.dumps(dict(case='approval-after-failure' if prior_failure else case,**custody_tip(f),history=history,terminal=terminal,proposal_binding=binding,requests=endpoint.requests,connections=endpoint.connections,
              trust='system' if case=='system-roots' else 'private mount: synthetic CA',
              ca_bundle_sha256=hashlib.sha256(Path('/etc/ssl/certs/ca-certificates.crt').read_bytes()).hexdigest(),
              ca_directory='/etc/ssl/certs', synthetic_leaf_sha256=ca,
              admissions=int(case=='approve'),permits=int(case=='approve'),competing_requests=0,roles_checked=sorted(roles),courier_fds=[0,1,2],descendants_reaped=True)),flush=True)


def interrupted_observation(install, test_root, case):
    proof=test_root/case
    proof.mkdir(mode=0o755)
    for name in ('provider_handoff.py','transport-normal'):
        os.link(install/name,proof/name)
    # Only this disposable installation uses a binary with a proof stop.
    edge='committed' if case=='tampered' else case
    shutil.copyfile(OUT/'reconcile'/('model-request-failure-'+edge),proof/'model-request')
    (proof/'model-request').chmod(0o555)
    with request_store() as f:
        command(f,'provision',['Ready'])
        genesis=f.verify()[2][32:]
        with started(proof,f) as (proc,source):
            assert source.recv(2)==b'K'
            fact,=replay(f,genesis,[18])
            courier,=children(proc.pid)
            issuer,=[p for p in children(courier) if Path(f'/proc/{p}/exe').resolve().name=='model-request']
            source.sendall(b'N')
            if case=='retry':
                out,err=proc.communicate(timeout=8)
                assert proc.returncode!=0 and not err and out.splitlines()==[
                    b'Retry Recorded Reconciliation',b'ProviderFailure CredentialUnavailable CountsUnavailable']
                history=check_failed_issuance(f,install,genesis,fact,'no-credential')
                print(json.dumps(dict(observation_case=case,**custody_tip(f),history=history)),flush=True)
                return
            until=time.monotonic()+8
            while time.monotonic()<until:
                if 'T (stopped)' in Path(f'/proc/{issuer}/status').read_text(): break
                time.sleep(.01)
            else: raise TimeoutError('missing observation stop')
            os.kill(issuer,signal.SIGKILL)
            out,err=proc.communicate(timeout=8)
            assert proc.returncode!=0 and not out and not err  # No acknowledgment before Confirm.
        pending=f.verify()
        assert pending[2][24:32]==fact[32:40] and pending[3]
        wires=[row[0] for row in f.query('SELECT canonical_event FROM events ORDER BY sequence')]
        assert wires[0]==fact and len(wires)==(1 if case=='prepared' else 2)
        if len(wires)==2: check_observation(wires[1],fact,False)
        if case=='tampered':
            bad=bytearray(wires[1])
            bad[104]=1  # Another *valid* profile, under the original pledge.
            f.query('UPDATE events SET canonical_event=? WHERE sequence=?',(bad,wires[1][32:40]))
            wires[1]=bytes(bad)
        if case=='committed':
            command(f,'recover',['Recorded','Expired','Ready'])
            events=replay(f,genesis,[18,20,19])
            assert events[:2]==wires and events[-1][56:105]==fact[8:40]+fact[56:72]+b'\x03'
            settled=f.verify()
            command(f,'recover',['Ready'])
            assert f.verify()==settled and replay(f,genesis,[18,20,19])==events
            wires=events
        else:
            command(f,'recover',['Reconciliation'],1)
            assert f.verify()==pending and f.query('SELECT canonical_event FROM events ORDER BY sequence')==[(w,) for w in wires]
        assert not list((f.root/'attempts').iterdir()) and not f.query('SELECT request_id FROM consumed_requests')
        assert len(f.query('SELECT wire FROM request_facts'))==(2 if case=='committed' else 1)
        print(json.dumps(dict(observation_case=case,**custody_tip(f),history=[w.hex() for w in wires],
                              pending=bool(f.verify()[3]))),flush=True)


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
        with tempfile.TemporaryDirectory(dir='/var/lib') as variants:
            test_root=Path(variants); test_root.chmod(0o755)
            for case in ('retry','prepared','committed','tampered'):
                interrupted_observation(install,test_root,case)
        assert dns.queries==[1,28,1,28]  # No new query since the system-roots control.
        bundle='/etc/ssl/certs/ca-certificates.crt'
        subprocess.run(['mount','--bind',cert,bundle],check=True)
        try:
            assert hashlib.sha256(Path(bundle).read_bytes()).hexdigest()==ca
            for case in ('approve','issuer-death','courier-death'): run_case(install,tls,dns,ca,case)
            run_case(install,tls,dns,ca,'approve',prior_failure=True)
        finally:
            subprocess.run(['umount',bundle],check=True)


def grade_histories(directory):
    # Rebuild the event chain from the retained canonical bytes and compare it
    # to the separately read custody checkpoint. Keep a pending tail outside it.
    rows=[json.loads(s) for s in (directory/'cases.jsonl').read_text().splitlines() if s.startswith('{')]
    rows=[r for r in rows if 'case' in r or 'observation_case' in r]
    expected={'no-credential':[18,20,19], 'system-roots':[18,20,19], 'approve':[18,1,11,12,13],
              'issuer-death':[18,19], 'courier-death':[18,19], 'approval-after-failure':[18,20,19,18,1,11,12,13],
              'prepared':[18], 'committed':[18,20,19], 'tampered':[18,20], 'retry':[18,20,19]}
    names=[r.get('case',r.get('observation_case')) for r in rows]
    assert len(names)==len(expected) and set(names)==set(expected)
    digest=lambda b:hashlib.sha256(b).digest()
    for name,row in zip(names, rows):
        wires=[bytes.fromhex(text) for text in row['history']]
        assert [wire[6] for wire in wires]==expected[name]
        cp=bytes.fromhex(row['checkpoint'])
        pledge=bytes.fromhex(row['pledge'])
        assert len(cp)==64 and bool(pledge)==(name in ('prepared','tampered'))
        head=wires[0][-32:]
        issuance=None
        for seq,wire in enumerate(wires,1):
            ref=cp[:24]+struct.pack('<Q',seq)
            assert wire[8:40]==ref and wire[-32:]==head
            if wire[6]==18: issuance=wire
            elif wire[6]==19: assert wire[56:105]==issuance[8:40]+issuance[56:72]+b'\3'
            elif wire[6]==20:
                if name=='tampered':
                    assert wire[104]==1 and pledge[:64]==cp and pledge[64:72]==ref[24:]
                    assert digest(b'warband.event.v1\0'+wire[:-32])!=pledge[104:]
                    original=bytearray(wire); original[104]=2
                    check_observation(original,issuance,False)
                    assert digest(b'warband.event.v1\0'+original[:-32])==pledge[104:]
                    break
                check_observation(wire,issuance,name=='system-roots')
            head=digest(b'warband.link.v1\0'+ref+head+digest(b'warband.event.v1\0'+wire[:-32]))
        count=1 if pledge else len(wires)
        assert cp[24:]==struct.pack('<Q',count)+head
        if pledge:
            assert len(pledge)==136 and pledge[:72]==cp+struct.pack('<Q',count+1)
            assert pledge[72:104]==digest(b'warband.link.v1\0'+cp[:24]+pledge[64:72]+head+pledge[104:])
        if name in ('approve','approval-after-failure'):
            proposal,decision,permit=wires[-3:]
            fp=digest(b'warband.marker.proposal.v1\0'+proposal[8:40]+proposal[56:-32])
            assert decision[56:120]==proposal[8:40]+fp and permit[56:88]==decision[8:40]
            assert row['proposal_binding']==[proposal[8:40].hex(),fp.hex()] and row['permits']==1
    print(json.dumps(dict(histories=len(rows),valid_confirmed_observations=sum(
        bytes.fromhex(wire)[6]==20 for r in rows if r.get('observation_case')!='tampered' for wire in r['history']),
        pending_missing=1,pending_altered=1)),flush=True)


if __name__=='__main__':
    if not __debug__: raise SystemExit('qualification requires assertions')
    if len(sys.argv)==3 and sys.argv[1]=='--grade-histories':
        grade_histories(Path(sys.argv[2]))
    else:
        main(Path(sys.argv[1]).resolve(strict=True))
