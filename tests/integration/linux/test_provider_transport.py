"""Offline ADR-0012 fixture. Run as Linux root with --self-test or --driver PATH.

Use --trusted-launcher PATH for the root-installed Odin bootstrap that forks the
two isolated roles. --driver PATH retains the original unprivileged test ABI. It inherits a
SEQPACKET issuer channel and a sealed synthetic credential via the numbered FDs
in WB_ISSUER_FD and WB_CREDENTIAL_FD. Its working directory has fixture-ca.pem.
The issuer sends one fixed tuple (see FRAME); C cancels. After R (Ready), S
delivers one connected FD via SCM_RIGHTS. The launcher returns one ASCII disposition packet, with NUL and the complete
response body appended for Ok in the original ABI. The trusted launcher returns
bounded counters, validated selection and the fixture response digest. Its grant
pipe contains one tuple and the connector sends the selected IPv4 address/port
with S. Exit status describes the driver, while disposition describes the call.
Only --self-test uses the built-in Python peer. It grades the apparatus itself.
"""
import argparse
import contextlib
import ctypes
import fcntl
import hashlib
import http.client
import http.server
import json
import os
from pathlib import Path
import re
import secrets
import select
import shutil
import signal
import socket
import socketserver
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time

HOST = 'api.openai.com'
PATH = '/v1/chat/completions'
TARGET = ('93.184.216.34', 443)  # assigned only to lo in a fresh, route-isolated netns
RID = b'0123456789abcdef0123456789abcdef'  # published 3a request vector
GOLDEN = '1c564761ec41d5562ec25b7e3b85e359eab68a48ee29416f7d7a2d4a3453c5b3'
FRAME = struct.Struct('<4s32sIIQ')  # magic, lowercase ID, catalog revision, example, BOOTTIME ms
MODEL = 'gpt-5.4-mini-2026-03-17'
CASES = {'success': 'Ok', 'duplicate': 'Ok', 'pre-cancel': 'Cancelled',
         'stall': 'Deadline', 'redirect': 'HttpFailure', 'proxy-env': 'Ok',
         'lost-reply': 'TransportFailure'}

PREFLIGHT = {'malformed':'InvalidHandoff','expired':'Deadline','bad-token':'CredentialUnavailable',
             'unsealed':'CredentialUnavailable','missing-token':'CredentialUnavailable','empty-token':'CredentialUnavailable','unknown-example':'InvalidProjection'}
TLS_CASES = {'untrusted':'TlsFailure','wrong-name':'TlsFailure','setup-stall':'Deadline',
             'wrong-peer':'SocketDenied','cancel-after-connect':'Cancelled'}
EXTENDED = {**PREFLIGHT, **TLS_CASES, 'cancel-after-send':'Cancelled','issuer-death':'IssuerLost',
            '401':'HttpFailure','407':'HttpFailure','417':'HttpFailure','429':'RateLimited',
            '500':'HttpFailure','header-at':'Ok','header-over':'HeaderLimit',
            'body-at':'Ok','body-over':'BodyLimit','compressed':'Framing','length-conflict':'Framing',
            'total-stall':'Deadline','bad-content':'Candidate.InvalidJson','bad-envelope':'Envelope.InvalidEnvelope'}


def now_ms():
    return time.clock_gettime_ns(time.CLOCK_BOOTTIME) // 1_000_000


def fixture_body():
    # Independent serialization, checked against 3a's complete 790-byte vector.
    fields = dict(schema_version={'type':'integer','enum':[1]}, request_id={'type':'string'},
                  action={'type':'string','enum':['create_marker']},
                  expected_effect={'type':'string','enum':['marker_contains_payload']},
                  payload_b64={'type':'string'})
    schema = dict(type='object', additionalProperties=False, required=list(fields), properties=fields)
    body = dict(model=MODEL, n=1, stream=False, store=False,
                response_format=dict(type='json_schema', json_schema=dict(name='marker_candidate', strict=True, schema=schema)),
                messages=[dict(role='developer', content='Return the marker proposal matching the schema. Echo the request ID and the Base64 payload exactly.'),
                          dict(role='user', content='request_id=' + RID.decode() + ' payload_b64=YWJj')])
    raw = json.dumps(body, separators=(',', ':')).encode()
    if hashlib.sha256(raw).hexdigest() != GOLDEN:
        raise ValueError('fixture projection differs from the reviewed vector')
    return raw


class Observer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True

    def __init__(self, address, handler):
        self.connections = self.requests = 0
        self.valid = True
        self.seen = threading.Event()
        self.release = threading.Event()
        self.lock = threading.Lock()
        super().__init__(address, handler)

    def get_request(self):
        sock, peer = super().get_request()
        sock.settimeout(4)
        self.connections += 1  # independent TCP accept, before TLS
        return sock, peer

    def handle_error(self, *_):
        exc=sys.exc_info()[1]
        if self.case in TLS_CASES and isinstance(exc,(ssl.SSLError, ConnectionError)):
            return
        self.valid = False  # avoid logging peer-controlled data


class Proxy(socketserver.BaseRequestHandler):
    def handle(self):
        pass  # TCP accept alone is a failure on the proxy-env arm


class Endpoint(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        if self.server.case=='setup-stall':
            self.server.release.wait(8)
            raise ConnectionResetError()
        self.request = self.server.tls.wrap_socket(self.request, server_side=True)
        super().setup()

    def log_message(self, *_):
        pass

    def parse_request(self):
        if not super().parse_request():
            self.server.valid = False
            return False
        with self.server.lock:
            self.server.requests += 1  # includes subsequent requests on this connection
            if self.command != 'POST':
                self.server.valid = False
        return True

    def do_POST(self):
        h = self.headers
        correct = (self.path == PATH and self.request_version == 'HTTP/1.1'
                   and h.get_all('Host') == [HOST] and h.get_all('Expect') is None
                   and h.get_all('Content-Type') == ['application/json']
                   and h.get_all('Authorization') == ['Bearer ' + self.server.token]
                   and h.get_all('Content-Length') == ['790'] and h.get_all('Accept') in (None, ['*/*'])
                   and all(k.lower() in {'host','content-type','authorization','content-length','accept'} for k in h))
        if not correct or hashlib.sha256(self.rfile.read(790)).hexdigest() != GOLDEN:
            self.server.valid = False
            self.close_connection = True
            return
        case = self.server.case
        self.server.seen.set()
        if case in ('stall', 'total-stall','cancel-after-send','issuer-death','lost-reply'):
            if case != 'lost-reply':
                self.server.release.wait(36)
            self.close_connection = True
            return
        if case in ('header-at','header-over'):
            interim=b'HTTP/1.1 103 Early Hints\r\n\r\n'
            first=b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nX-Pad: '
            end=b'\r\n\r\n'
            trailer=b'X-Trailer: done\r\n'
            pad=16384+int(case=='header-over')-len(interim+first+end+trailer)
            data=self.server.reply
            self.wfile.write(interim+first+b'x'*pad+end+f'{len(data):x}\r\n'.encode()+data+b'\r\n0\r\n'+trailer+b'\r\n')
            return
        self.send_response_only(int(case) if case.isdigit() else 307 if case == 'redirect' else 200)
        if case=='compressed': self.send_header('Content-Encoding','gzip')
        if case=='length-conflict': self.send_header('Transfer-Encoding','chunked')
        if case == 'redirect':
            self.send_header('Location', 'https://' + HOST + '/unexpected')
        body = b'' if case == 'redirect' else self.server.reply
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


@contextlib.contextmanager
def observing(server):
    thread = threading.Thread(target=server.serve_forever, args=(0.02,))
    thread.start()
    try:
        yield server
    finally:
        server.release.set()
        server.shutdown()
        thread.join()
        # Include any peers queued before the driver exited.
        while select.select([server.socket], [], [], 0)[0]:
            server.handle_request()
        server.server_close()  # joins handlers before inspecting totals


def self_test_peer(double):
    with socket.socket(fileno=int(os.environ['WB_ISSUER_FD'])) as channel:
        packet = channel.recv(FRAME.size + 1)
        magic, rid, revision, example, deadline = FRAME.unpack(packet)
        if (magic, rid, revision, example) != (b'WBT1', RID, 1, 2):
            raise ValueError('invalid fixture handoff')
        if select.select([channel], [], [], 0)[0]:
            control = channel.recv(FRAME.size + 1)
            if control == b'C':
                channel.sendall(b'Cancelled')
                return
            if control != packet:
                raise ValueError('unexpected issuer message')
        token = os.read(int(os.environ['WB_CREDENTIAL_FD']), 96).decode()
        body = fixture_body()
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.load_verify_locations('fixture-ca.pem')
        channel.sendall(b'R')
        while True:
            msg, fds, flags, _ = socket.recv_fds(channel, FRAME.size + 1, 1)
            if msg == packet and not fds and not flags:  # duplicate issuance at launcher
                continue
            if msg != b'S' or len(fds) != 1 or flags:
                raise ValueError('bad socket handoff')
            break
        outcome = b'Ok'
        with socket.socket(fileno=fds[0]) as tcp:
            if tcp.getpeername() != TARGET:
                raise ValueError('unexpected fixture peer')
            with ctx.wrap_socket(tcp, server_hostname=HOST) as tls:
                for _ in range(2 if double else 1):
                    remaining = (deadline - now_ms()) / 1000
                    if remaining <= 0:
                        outcome = b'Deadline'
                        break
                    tls.settimeout(remaining)
                    request = (f'POST {PATH} HTTP/1.1\r\nHost: {HOST}\r\nContent-Type: application/json\r\n'
                               f'Authorization: Bearer {token}\r\nContent-Length: {len(body)}\r\n\r\n').encode()
                    tls.sendall(request + body)
                    try:
                        with http.client.HTTPResponse(tls) as response:
                            response.begin()
                            content = response.read()
                            outcome = b'Ok\0' + content if response.status == 200 else b'HttpFailure'
                    except TimeoutError:
                        outcome = b'Deadline'
                    except http.client.RemoteDisconnected:
                        outcome = b'TransportFailure'
        channel.sendall(outcome)


def children(pid):
    return [int(v) for v in Path(f'/proc/{pid}/task/{pid}/children').read_text().split()]


def inventory(pid):
    roles={}
    for child in children(pid):
        proc=Path(f'/proc/{child}')
        uid=proc.stat().st_uid
        fds=[os.readlink(f) for f in (proc/'fd').iterdir()]
        if any('memfd:' in f or '/journal/' in f or 'custody' in f for f in fds):
            raise ValueError('unexpected inherited descriptor after Ready')
        roles[uid]=(child,os.stat(proc/'ns/net').st_ino)
    if set(roles)!={60001,60002} or roles[60001][1]==roles[60002][1]:
        raise ValueError('role isolation')
    return [p for p,_ in roles.values()]


def relay():
    # A separate issuer lifetime allows the observer to kill it and watch the
    # kernel reap the entire transfer without closing the observer itself.
    with socket.socket(fileno=int(os.environ['WB_ISSUER_FD'])) as observer:
        parent,child=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
        env=dict(os.environ,WB_ISSUER_FD=str(child.fileno()))
        grant,secret=int(env['WB_OPPORTUNITY_FD']),int(env['WB_CREDENTIAL_FD'])
        p=subprocess.Popen(['./driver'],env=env,pass_fds=(child.fileno(),grant,secret))
        child.close()
        os.close(grant); os.close(secret)
        with parent:
            parent.sendall(observer.recv(FRAME.size))
            if parent.recv(64)!=b'R': raise ValueError('launcher preflight')
            observer.sendall(b'R')
            msg,fds,_,_=socket.recv_fds(observer,16,1)
            socket.send_fds(parent,[msg],fds)
            for fd in fds: os.close(fd)
            p.wait(timeout=12)


def await_orphans(pids):
    pending=set(pids)
    until=time.monotonic()+3
    while pending and time.monotonic()<until:
        for pid in list(pending):
            try:
                dead,_=os.waitpid(pid,os.WNOHANG)
            except ChildProcessError:
                dead=pid if not Path(f'/proc/{pid}').exists() else 0
            if dead: pending.remove(dead)
        if pending: time.sleep(.01)
    if pending: raise ValueError('issuer left descendants')


def drive(root, command, case, proxy, endpoint):
    began=now_ms()
    deadline = began + (32_000 if case=='total-stall' else 0 if case=='expired' else 1800 if case=='stall' else 8000)
    packet = FRAME.pack(b'WBT0' if case=='malformed' else b'WBT1', RID, 1, 3 if case=='unknown-example' else 2, deadline)
    with contextlib.ExitStack() as stack:
        parent, child = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        stack.enter_context(parent)
        stack.enter_context(child)
        fd = os.memfd_create('fixture-token', os.MFD_ALLOW_SEALING | os.MFD_CLOEXEC)
        stack.callback(os.close, fd)
        grant, writer = os.pipe()
        stack.callback(os.close, grant)
        stack.callback(lambda: os.close(writer) if writer>=0 else None)
        os.write(fd,b'' if case=='empty-token' else b'bad\nvalue' if case=='bad-token' else endpoint.token.encode())
        os.lseek(fd, 0, os.SEEK_SET)
        if case!='unsealed':
            fcntl.fcntl(fd, fcntl.F_ADD_SEALS, fcntl.F_SEAL_SEAL | fcntl.F_SEAL_WRITE |
                    fcntl.F_SEAL_GROW | fcntl.F_SEAL_SHRINK)
        env = dict(PATH=os.defpath, WB_ISSUER_FD=str(child.fileno()), WB_CREDENTIAL_FD=str(fd), WB_OPPORTUNITY_FD=str(grant))
        if case=='missing-token': env.pop('WB_CREDENTIAL_FD')
        if case == 'proxy-env':
            url = 'http://127.0.0.1:' + str(proxy.server_address[1])
            keylog=root/'fixture-keylog'
            keylog.touch(); keylog.chmod(0o666)
            env.update(https_proxy=url, HTTPS_PROXY=url, ALL_PROXY=url, SSLKEYLOGFILE=str(keylog))
        parent.sendall(packet)
        if case == 'pre-cancel':
            parent.sendall(b'C')
        if case == 'duplicate':
            parent.sendall(packet)
        def spawn(sock, argv):
            proc=subprocess.Popen(argv,cwd=root,env=dict(env,WB_ISSUER_FD=str(sock.fileno())),
                pass_fds=(sock.fileno(),fd,grant),user=0 if endpoint.bootstrap else 65534,
                group=0 if endpoint.bootstrap else 65534,extra_groups=[],start_new_session=True,
                stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            stack.callback(stop,proc)
            sock.close()
            return proc
        def stop(proc):
            if proc.poll() is None:
                with contextlib.suppress(ProcessLookupError): os.killpg(proc.pid,signal.SIGKILL)
            proc.wait(timeout=4)
            proc.stdout.close(); proc.stderr.close()
        p=spawn(child,[sys.executable,str(Path(__file__).resolve()),'--issuer-relay'] if case=='issuer-death' else command)
        if case=='duplicate' and endpoint.bootstrap:
            rival,other=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
            stack.enter_context(rival)
            rival.sendall(packet)
            second=spawn(other,command)
            os.write(writer,packet)
            # Release EOF to both readers after the atomic grant is available.
            os.close(writer); writer=-1
            for sock in (parent,rival): sock.settimeout(4)
            one,two=parent.recv(64,socket.MSG_PEEK),rival.recv(64,socket.MSG_PEEK)
            if sorted((one,two))!=[b'R',b'Spent']: raise ValueError('duplicate grant')
            if two==b'R': parent,p=rival,second
        else:
            os.write(writer,packet)
            os.close(writer); writer=-1
        if case=='issuer-death' and ctypes.CDLL(None).prctl(36,1,0,0,0)!=0:
            raise OSError('subreaper unavailable')
        try:
            while True:
                parent.settimeout(max(0.001,(deadline+2000-now_ms())/1000))
                msg, _, flags, _ = parent.recvmsg(64 * 1024 + 64)
                if flags:
                    raise ValueError('truncated driver packet')
                if msg != b'R':
                    break
                if endpoint.attempts or now_ms() >= deadline or case == 'pre-cancel':
                    raise ValueError('unexpected connector request')
                endpoint.attempts += 1
                if endpoint.bootstrap:
                    launcher=children(p.pid)[0] if case=='issuer-death' else p.pid
                    # The front end may still be completing its post-fork UID drop.
                    until=time.monotonic()+1
                    while True:
                        try:
                            descendants=inventory(launcher)
                            break
                        except (ValueError,FileNotFoundError):
                            if time.monotonic()>=until: raise
                            time.sleep(.005)
                if case in PREFLIGHT:
                    raise ValueError('preflight attempted TCP')
                with socket.create_connection(TARGET, timeout=1) as tcp:
                    if case=='cancel-after-connect':
                        parent.sendall(b'C')
                        continue
                    peer=socket.inet_aton('93.184.216.35' if case=='wrong-peer' else TARGET[0])+struct.pack('!H',443)
                    socket.send_fds(parent,[b'S'+peer if endpoint.bootstrap else b'S'],[tcp.fileno()])
                if case=='issuer-death':
                    if not endpoint.seen.wait(3): raise TimeoutError('endpoint receipt')
                    p.kill(); p.wait(timeout=2)
                    await_orphans([launcher,*descendants])
                    return 'IssuerLost'
                if case=='cancel-after-send':
                    if not endpoint.seen.wait(3): raise TimeoutError('endpoint receipt')
                    parent.sendall(b'C')
            if endpoint.bootstrap and msg not in (b'InvalidHandoff',b'CredentialUnavailable',b'Deadline',b'Spent'):
                if len(msg)<17: raise ValueError('short transfer record')
                status,sent,headers,received=struct.unpack('<IIII',msg[:16])
                if status>599 or sent>16384 or headers>16384 or received>65536: raise ValueError('invalid transfer counts')
                endpoint.metrics=dict(http_status=status, uploaded=sent, headers=headers, body=received)
                msg=msg[16:]
                if msg.startswith(b'Ok\0'):
                    expected = hashlib.sha256(endpoint.reply).digest()+RID+struct.pack('<II',2,3)
                    if msg[3:] != expected or sent!=790 or received!=len(endpoint.reply) or status!=200:
                        raise ValueError('incorrect front-end selection or transfer counts')
                    msg=b'Ok\0'+endpoint.reply
            if msg.startswith(b'Ok\0') and msg[3:] == endpoint.reply:
                msg = b'Ok'
            elif msg == b'Ok':
                raise ValueError('missing response body')
            if msg not in {v.encode() for v in (*CASES.values(),*EXTENDED.values())}:
                raise ValueError('unknown disposition')
            elapsed=now_ms()-began
            if case=='setup-stall' and not 5000<=elapsed<7000: raise ValueError('setup deadline')
            if case=='total-stall' and not 30000<=elapsed<32000: raise ValueError('total deadline')
            if case == 'stall' and now_ms() < deadline:
                raise ValueError('premature deadline disposition')
            if case=='proxy-env' and keylog.stat().st_size: raise ValueError('TLS key log disclosure')
            if p.wait(timeout=2) != 0 or p.stdout.read(1) or p.stderr.read(1):
                raise ValueError('driver exit')
            if case=='duplicate' and endpoint.bootstrap:
                again,end=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
                with again:
                    again.sendall(packet)
                    retry=spawn(end,command)
                    again.settimeout(2)
                    if again.recv(64)!=b'Spent' or retry.wait(timeout=2)!=0: raise ValueError('restart reused opportunity')
            return msg.decode()
        finally:
            if p.poll() is None: stop(p)


def exercise(root, command, tls, case, mutant=False, bootstrap=False):
    endpoint = Observer(TARGET, Endpoint)
    endpoint.tls, endpoint.case, endpoint.token = tls, case, secrets.token_hex(24)
    endpoint.attempts,endpoint.bootstrap,endpoint.metrics = 0,bootstrap,{}
    proposal = dict(schema_version=1, request_id=RID.decode(), action='create_marker',
                    expected_effect='marker_contains_payload', payload_b64='YWJj')
    message = dict(role='assistant', content=json.dumps(proposal))
    endpoint.reply = json.dumps(dict(object='chat.completion', model=MODEL, id=secrets.token_hex(12),
                                     choices=[dict(index=0, finish_reason='stop', message=message)])).encode()
    if case in ('body-at','body-over'):
        endpoint.reply=endpoint.reply.ljust(65536+int(case=='body-over'),b' ')
    if case=='bad-envelope': endpoint.reply=b'{}'
    if case=='bad-content':
        endpoint.reply=json.dumps(
            dict(object='chat.completion',model=MODEL,choices=[dict(index=0,finish_reason='stop',message=dict(role='assistant',content='!'))])).encode()
    with observing(endpoint), observing(Observer(('127.0.0.1',0), Proxy)) as proxy:
        # Establish that the proxy trap is reachable before launching the subject.
        with socket.create_connection(proxy.server_address, timeout=1):
            pass
        until = time.monotonic() + 2
        while not proxy.connections:
            if time.monotonic() >= until:
                raise TimeoutError('proxy positive control')
            time.sleep(.01)
        try:
            result = drive(root, command, case, proxy, endpoint)
        except (OSError, ValueError, subprocess.SubprocessError) as exc:
            result = type(exc).__name__  # retain the observer's counts even if the driver disappears
    proxy_attempts = proxy.connections - 1
    want = int(case not in PREFLIGHT and case!='pre-cancel' and case not in TLS_CASES)
    connects=int(case not in PREFLIGHT and case!='pre-cancel')
    expected={**CASES,**EXTENDED}[case]
    passed = (result == expected and endpoint.attempts == endpoint.connections == connects and endpoint.requests == want
              and endpoint.valid and proxy_attempts == 0)
    if case.isdigit():
        passed &= endpoint.metrics.get('http_status')==int(case)
    if case=='header-at':
        passed &= endpoint.metrics.get('headers')==16384
    if case=='body-at':
        passed &= endpoint.metrics.get('body')==65536
    if mutant:
        passed = not passed and endpoint.valid and result == 'Ok' and endpoint.attempts == endpoint.connections == 1 and endpoint.requests == 2
    return dict(case='detect-double-send' if mutant else case, passed=passed, disposition=result,
                connector_attempts=endpoint.attempts, connections=endpoint.connections, requests=endpoint.requests,
                proxy_connections=proxy_attempts, request_shape_valid=endpoint.valid,**endpoint.metrics)


def verify_public_chain(root, fixture_ca, vectors):
    # Offline Go x509 "Valid" vector. The historical validation time is part of the vector.
    source=vectors.read_bytes()
    certs=[]
    for name in (b'googleLeaf',b'gtsIntermediate'):
        pem=re.search(rb'const '+name+rb' = `(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)',source,re.S)[1]
        path=root/name.decode()
        path.write_bytes(pem+b'\n')
        certs.append(path)
    opts=['openssl','verify','-no-CApath','-no-CAstore','-attime','1677615892','-purpose','sslserver',
          '-verify_hostname','www.google.com','-untrusted',str(certs[1])]
    for ca,expect in ((Path('/etc/ssl/certs/ca-certificates.crt'),True),(fixture_ca,False)):
        result=subprocess.run([*opts,'-CAfile',ca,certs[0]],capture_output=True)
        if (result.returncode==0)!=expect:
            raise ValueError('offline public-chain verification disagrees')
    print(json.dumps(dict(subject='offline-chain',hostname='www.google.com',validation_time=1677615892,
          leaf_sha256=hashlib.sha256(certs[0].read_bytes()).hexdigest(),issuer_sha256=hashlib.sha256(certs[1].read_bytes()).hexdigest(),
          vectors_sha256=hashlib.sha256(source).hexdigest(),production_bundle='accepted',fixture_bundle='rejected')),flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--driver', type=Path, help='fixture launcher executable implementing the inherited-FD interface')
    mode.add_argument('--trusted-launcher', type=Path, help='root-installed fixture bootstrap that drops child UIDs')
    mode.add_argument('--self-test', action='store_true')
    parser.add_argument('--public-vectors',type=Path,help='Go crypto/x509/verify_test.go with googleLeaf and gtsIntermediate')
    parser.add_argument('--production-roots',action='store_true',help='test fixture refusal with production trust settings')
    parser.add_argument('--isolated', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    script = Path(__file__).resolve()
    if not args.isolated:
        return subprocess.call(['unshare','--net',sys.executable,script,'--isolated',*sys.argv[1:]])
    if os.geteuid() or os.stat('/proc/self/ns/net').st_ino == os.stat('/proc/1/ns/net').st_ino or socket.if_nameindex() != [(1,'lo')]:
        parser.error('requires a fresh loopback-only Linux network namespace')
    subprocess.run(['ip','link','set','lo','up'],check=True)
    subprocess.run(['ip','address','add',TARGET[0]+'/32','dev','lo'],check=True)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        key = root/'private'/'key.pem'
        key.parent.mkdir(mode=0o700)
        cert = root/'fixture-ca.pem'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN='+HOST,
                        '-addext','subjectAltName=DNS:'+HOST,'-keyout',key,'-out',cert],
                       check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.minimum_version = ssl.TLSVersion.TLSv1_2
        tls.load_cert_chain(cert,key)
        (root/'fixture-empty-roots').mkdir(mode=0o755)
        root.chmod(0o755)
        cert.chmod(0o644)
        wrong=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        # Keep the fixture root trusted but issue a leaf for a different name.
        csr=root/'wrong.csr'; leaf=root/'wrong.pem'
        quiet=dict(check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        subprocess.run(['openssl','req','-new','-key',key,'-subj','/CN=wrong.invalid','-out',csr],**quiet)
        subprocess.run(['openssl','x509','-req','-in',csr,'-CA',cert,'-CAkey',key,'-set_serial','2','-days','1','-out',leaf],**quiet)
        wrong.load_cert_chain(leaf,key)
        if args.public_vectors:
            verify_public_chain(root,cert,args.public_vectors)
        dest = root/'driver'
        if args.trusted_launcher:
            binary = args.trusted_launcher.resolve(strict=True)
            for path in (binary,*binary.parents):
                st=path.stat()
                if st.st_uid or st.st_mode & 0o022:
                    parser.error('trusted launcher requires a root-owned, protected installation')
        shutil.copyfile(args.trusted_launcher or args.driver or script,dest)
        dest.chmod(0o555)
        command = [str(dest)] if args.driver or args.trusted_launcher else [sys.executable,str(dest),'--peer']
        success = True
        cases=list(CASES)
        if args.trusted_launcher:
            cases=['untrusted'] if args.production_roots else [*cases,*[k for k in EXTENDED if k!='untrusted']]
        if args.self_test: cases.append('mutant')
        for case in cases:
            try:
                row = exercise(root, command+(['--double'] if case=='mutant' else []), wrong if case=='wrong-name' else tls,
                               'success' if case=='mutant' else case, case=='mutant',bool(args.trusted_launcher))
            except (OSError, ValueError, subprocess.SubprocessError) as exc:
                row = dict(case=case,passed=False,error=type(exc).__name__)
            print(json.dumps(dict(subject='oracle-self-test' if args.self_test else 'external-driver',fixture_ca_sha256=hashlib.sha256(cert.read_bytes()).hexdigest(),**row)),flush=True)
            success &= row['passed']
        return int(not success)


if __name__ == '__main__':
    if sys.argv[1:] == ['--issuer-relay']:
        relay()
    elif sys.argv[1:2] == ['--peer']:
        self_test_peer(sys.argv[2:] == ['--double'])
    else:
        sys.exit(main())
