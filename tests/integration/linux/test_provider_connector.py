"""Qualify the real fixed-destination connector in a fresh, unrouted Linux namespace."""
import contextlib
import fcntl
import ipaddress
import json
import os
import re
import select
from pathlib import Path
import shutil
import socket
import socketserver
import ssl
import struct
import subprocess
import sys
import hashlib
import tempfile
import time

import test_provider_transport as fixture

TARGET = fixture.TARGET
STUB = ('127.0.0.53', 53)
OTHER = '93.184.216.35'
V6 = '2606:4700::1111'
BLOCKED = ['0.0.0.0','10.0.0.1','100.64.0.1','127.0.0.1','169.254.1.1','172.31.0.1',
           '192.0.2.1','192.168.1.1','198.18.0.1','198.51.100.1','203.0.113.1','224.0.0.1','255.255.255.255',
           '::','::1','::ffff:127.0.0.1','::ffff:10.0.0.1','64:ff9b::a00:1','fc00::1','fe80::1','ff02::1',
           '2001:db8::1','2002::1','3fff::1','3ffe::1','3000::1','2001:1000::1']


class DNS(socketserver.StreamRequestHandler):
    def handle(self):
        size=self.rfile.read(2)
        if len(size)!=2: return
        q=self.rfile.read(int.from_bytes(size,'big'))
        if q[12:-4]!=b'\x03api\x06openai\x03com\x00' or q[-2:]!=b'\x00\x01':
            self.server.valid=False
            return
        kind=int.from_bytes(q[-4:-2],'big')
        if kind not in (1,28):
            self.server.valid=False
            return
        with self.server.lock:
            case=self.server.case
            ix=len(self.server.queries)
            self.server.queries.append(kind)
        if self.server.hold:
            self.server.release.wait(7)
        if case=='cancel-dns': return
        if case=='stall':
            self.server.release.wait(7)
            return
        addresses={1:[TARGET[0]],28:[V6]}
        if case=='reorder':
            addresses[1]=[TARGET[0],OTHER] if ix==0 else [OTHER,TARGET[0]]
        elif case=='changed' and ix>=2: addresses[1]=[OTHER]
        elif case=='no-fallback': addresses[1]=['93.184.216.33',TARGET[0]]
        elif case=='private-only': addresses[1]=['10.0.0.1']
        elif case=='ipv6-only': addresses[1]=[]
        elif case in BLOCKED:
            addresses[1 if ipaddress.ip_address(case).version==4 else 28].append(case)
        elif case in ('nodata','incomplete'): addresses[28]=[]
        answers=bytearray()
        owner=b'\xc0\x0c'
        aliases=0
        if case in ('cname','changed-alias','cname-loop'):
            labels=['first' if case!='changed-alias' or ix<2 else 'other','stable']
            if case=='cname-loop': labels=['first','first']
            for label in labels:
                target=bytes([len(label)])+label.encode()+b'\xc0\x0c'
                answers.extend(owner+struct.pack('!HHIH',5,1,60,len(target))+target)
                owner=target
                aliases+=1
        for addr in addresses[kind]:
            raw=ipaddress.ip_address(addr).packed
            answers.extend(owner+struct.pack('!HHIH',kind,1,60,len(raw))+raw)
        flags={'truncated':0x8380,'servfail':0x8182}.get(case,0x8180)
        soa=b'\xc0\x0c'+struct.pack('!HHIH',6,1,60,24)+b'\xc0\x0c'*2+bytes(20) if not addresses[kind] and case!='incomplete' else b''
        packet=q[:2]+struct.pack('!HHHHH',flags,1,len(addresses[kind])+aliases,int(bool(soa)),0)+q[12:]+answers+soa
        if case=='bad-length': packet+=b'x'
        self.wfile.write(struct.pack('!H',len(packet))+packet)


def positive_control(address):
    subprocess.run([sys.executable,'-c',
                    'import socket,sys; socket.create_connection((sys.argv[1],int(sys.argv[2])),1).close()',
                    address[0],str(address[1])],user=60001,group=60001,extra_groups=[],check=True)


def run_case(root,driver,tls,dns,case):
    from test_provider_transport import Observer, Endpoint, observing, FRAME, RID, MODEL, now_ms
    endpoint=Observer(TARGET, Endpoint)
    names=[]
    tls.set_servername_callback(lambda sock,name,ctx: names.append(name))
    endpoint.tls=tls
    endpoint.case='lost-reply' if case=='lost-reply' else 'success'
    endpoint.token=os.urandom(24).hex()
    content=dict(schema_version=1,request_id=RID.decode(),action='create_marker',
                 expected_effect='marker_contains_payload',payload_b64='YWJj')
    endpoint.reply=json.dumps(dict(object='chat.completion', model=MODEL,choices=[
        dict(index=0,finish_reason='stop',message=dict(role='assistant',content=json.dumps(content)))])).encode()
    until=now_ms()+(0 if case=='expired' else 8000)
    packet=FRAME.pack(b'WBT1',RID,1,3 if case=='unknown-example' else 2,until)
    dns.case, dns.queries = case,[]
    with contextlib.ExitStack() as stack:
        stack.enter_context(observing(endpoint))
        ctl,child=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
        stack.enter_context(ctl); stack.enter_context(child)
        secret=os.memfd_create('synthetic',os.MFD_CLOEXEC|os.MFD_ALLOW_SEALING)
        stack.callback(os.close,secret)
        os.write(secret,endpoint.token.encode())
        fcntl.fcntl(secret,fcntl.F_ADD_SEALS,15)
        grant,writer=os.pipe()
        stack.callback(os.close,grant)
        os.write(writer,packet); os.close(writer)
        env=dict(WB_ISSUER_FD=str(child.fileno()),WB_CREDENTIAL_FD=str(secret),WB_OPPORTUNITY_FD=str(grant),
                 HTTPS_PROXY='http://127.0.0.1:8080',https_proxy='http://127.0.0.1:8080')
        ctl.sendall(packet)
        if case=='pre-cancel': ctl.sendall(b'C')
        if case=='injected-url': ctl.sendall(b'https://unexpected.invalid:8443/')
        if case=='injected-address': ctl.sendall(b'S'+socket.inet_aton('127.0.0.1')+struct.pack('!H',443))
        if case=='injected-fd': socket.send_fds(ctl,[b'S'+socket.inet_aton(TARGET[0])+struct.pack('!H',443)],[grant])
        dns.hold=case in ('control','cancel-dns')
        dns.release.clear()
        p=subprocess.Popen([driver],cwd=root,pass_fds=(child.fileno(),secret,grant),env=env,
                           stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        child.close()
        roles={}
        try:
            if dns.hold:
                for _ in range(300):
                    if dns.queries: break
                    time.sleep(.005)
                assert dns.queries
                if case=='control':
                    for pid in fixture.children(p.pid):
                        proc=Path(f'/proc/{pid}')
                        status=dict(line.split(':',1) for line in (proc/'status').read_text().splitlines() if ':' in line)
                        uid=int(status['Uid'].split()[1])
                        roles[uid]=dict(pid=pid,netns=os.stat(proc/'ns/net').st_ino,seccomp=int(status['Seccomp']),
                                        capabilities=int(status['CapEff'],16),nnp=int(status['NoNewPrivs']))
                        assert not any('memfd:' in os.readlink(fd) for fd in (proc/'fd').iterdir())
                    assert set(roles)=={60001,60002,60003} and len({v['netns'] for v in roles.values()})==3
                    assert all(v['nnp']==1 and v['capabilities']==0 for v in roles.values())
                    assert all(roles[uid]['seccomp']==2 for uid in (60001,60002))
                else: ctl.sendall(b'C')
                if case=='control': dns.release.set()
            ctl.settimeout(10)
            msg=ctl.recv(200)
            assert p.wait(timeout=2)==0 and p.stdout.read()==p.stderr.read()==b''
        finally:
            dns.release.set()
            if p.poll() is None: p.kill()
            p.wait(timeout=3)
    want={'expired':'Deadline','unknown-example':'InvalidProjection','pre-cancel':'Cancelled','cancel-dns':'Cancelled','stall':'Deadline','lost-reply':'TransportFailure',
          'injected-address':'InvalidHandoff','injected-fd':'InvalidHandoff','injected-url':'InvalidHandoff',
          'unprivileged-stub':'ResolutionUnavailable','incomplete':'ResolutionUnavailable','servfail':'ResolutionUnavailable','cname-loop':'ResolutionUnavailable','truncated':'ResolutionUnavailable',
          'bad-length':'ResolutionUnavailable','no-fallback':'ConnectFailure'}.get(case,'DestinationDenied')
    if case in ('control','reorder','cname','nodata'): want='Ok'
    if msg not in (b'Cancelled',b'Deadline',b'InvalidHandoff'):
        assert len(msg)>=17
        code,uploaded,headers,body=struct.unpack('<IIII',msg[:16])
        msg=msg[16:]
        if want=='Ok':
            assert msg==b'Ok\0'+hashlib.sha256(endpoint.reply).digest()+RID+struct.pack('<II',2,3)
            assert code==200 and uploaded==790 and body==len(endpoint.reply)
            msg=b'Ok'
    assert msg==want.encode(),(case,want,msg[:32])
    sent=int(case in ('control','reorder','cname','nodata','lost-reply'))
    assert endpoint.valid and endpoint.connections==endpoint.requests==sent,(case,endpoint.connections,endpoint.requests)
    if case in ('pre-cancel','expired','unknown-example','unprivileged-stub','injected-address','injected-fd','injected-url'): assert not dns.queries
    elif case in ('stall','cancel-dns'): assert dns.queries==[1]
    elif case=='incomplete': assert dns.queries==[1,28]
    elif case not in ('truncated','servfail','bad-length','cname-loop'): assert dns.queries==[1,28,1,28]
    assert dns.valid and names==[fixture.HOST]*sent
    print(json.dumps(dict(case=case,disposition=want,dns=dns.queries,connections=endpoint.connections,
                          requests=endpoint.requests,roles=roles)),flush=True)


def verify_traces(directory, results):
    records=[json.loads(line) for line in Path(results).read_text().splitlines()]
    roles=next(r['roles'] for r in records if r['case']=='control')
    expected_dns=sum(len(r['dns']) for r in records)
    expected_tcp=sum(r['connections'] for r in records)
    ports=[]
    for trace in Path(directory).glob('trace.*'):
        lines=trace.read_text().splitlines()
        if not any(l.startswith('setresuid(60003,') for l in lines): continue
        calls=[l for l in lines if l.startswith('connect(')]
        for call in calls:
            peer=re.search(r'sin_port=htons\((\d+)\).*inet_addr\("([0-9.]+)"\)',call)
            assert peer,call
            ports.append((peer[2],int(peer[1])))
    assert ports.count(STUB)==expected_dns and ports.count(TARGET)==expected_tcp
    refused=('93.184.216.33',443)
    assert ports.count(refused)==1 and set(ports)=={STUB,TARGET,refused}
    for uid in ('60001','60002'):
        lines=(Path(directory)/f"trace.{roles[uid]['pid']}").read_text().splitlines()
        for family,kind in [('AF_INET','SOCK_STREAM'),('AF_INET','SOCK_DGRAM'),('AF_INET6','SOCK_STREAM'),('AF_UNIX','SOCK_STREAM')]:
            assert any(l.startswith(f'socket({family}, {kind}') and 'EPERM' in l for l in lines)
        attempts=[l for l in lines if l.startswith('connect(')]
        assert len(attempts)==1 and 'local.sock' in attempts[0] and 'EPERM' in attempts[0]
    print(json.dumps(dict(graded=len(records),trusted_dns_connections=expected_dns,tls_connections=expected_tcp,
                          refused_connects=1,additional_attempts=0,filtered_roles=2)))


def main():
    if len(sys.argv)!=2 or os.geteuid() or socket.if_nameindex()!=[(1,'lo')] or os.stat('/proc/self/ns/net').st_ino==os.stat('/proc/1/ns/net').st_ino:
        raise SystemExit('requires root in a fresh isolated network namespace and a root-installed launcher')
    driver=Path(sys.argv[1]).resolve(strict=True)
    for path in (driver,*driver.parents):
        assert path.stat().st_uid==0 and not path.stat().st_mode & 0o022
    subprocess.run(['ip','link','set','lo','up'],check=True)
    for ip in (TARGET[0],OTHER,'93.184.216.33','10.0.0.1','169.254.1.1'):
        subprocess.run(['ip','addr','add',ip+'/32','dev','lo'],check=True)
    with tempfile.TemporaryDirectory() as tmp,contextlib.ExitStack() as stack:
        root=Path(tmp); key=root/'private/key'
        driver=Path(shutil.copyfile(driver,root/'launcher')); driver.chmod(0o555)
        key.parent.mkdir(mode=0o700)
        cert=root/'fixture-ca.pem'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN='+fixture.HOST,
                        '-addext','subjectAltName=DNS:'+fixture.HOST,'-keyout',key,'-out',cert],
                       stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True)
        root.chmod(0o755); cert.chmod(0o644); (root/'fixture-empty-roots').mkdir()
        tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(cert,key)
        traps=[]
        for addr in ((OTHER,443),('10.0.0.1',443),('169.254.1.1',443),('127.0.0.1',443),
                     (TARGET[0],8443),('127.0.0.1',8080)):
            trap=stack.enter_context(fixture.observing(fixture.Observer(addr,fixture.Proxy)))
            positive_control(addr)
            for _ in range(100):
                if trap.connections: break
                time.sleep(.01)
            assert trap.connections==1
            traps.append(trap)
        local=stack.enter_context(socket.socket(socket.AF_UNIX,socket.SOCK_STREAM))
        path=root/'local.sock'
        local.bind(str(path)); path.chmod(0o666); local.listen(2); local.settimeout(1)
        subprocess.run([sys.executable,'-c',"import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])",path],
                       user=60001,group=60001,extra_groups=[],check=True)
        local.accept()[0].close()
        dns=stack.enter_context(fixture.observing(fixture.Observer(STUB,DNS)))
        dns.hold=False
        for case in ('control','reorder','cname','nodata','changed','changed-alias','no-fallback','private-only','ipv6-only',*BLOCKED,
                     'truncated','servfail','bad-length','cname-loop','incomplete','injected-url','injected-fd','injected-address','pre-cancel','expired','unknown-example','cancel-dns','stall','lost-reply'):
            run_case(root,driver,tls,dns,case)
            assert all(t.connections==1 for t in traps) and not select.select([local],[],[],0)[0]
        low_port=Path('/proc/sys/net/ipv4/ip_unprivileged_port_start')
        previous=low_port.read_text()
        try:
            low_port.write_text('0')
            run_case(root,driver,tls,dns,'unprivileged-stub')
        finally:
            low_port.write_text(previous)


if __name__=='__main__':
    if not __debug__: raise RuntimeError('qualification requires assertions')
    if sys.argv[1:2]==['--verify-traces']:
        verify_traces(*sys.argv[2:])
    else:
        main()
