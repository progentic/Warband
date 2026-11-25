"""Offline ADR-0012 fixture. Run as Linux root with --self-test or --driver PATH.

The fixture driver is a child launcher under an unprivileged UID. It inherits a
SEQPACKET issuer channel and a sealed synthetic credential via the numbered FDs
in WB_ISSUER_FD and WB_CREDENTIAL_FD. Its working directory has fixture-ca.pem.
The issuer sends one fixed tuple (see FRAME); C cancels. After R (Ready), S
delivers one connected FD via SCM_RIGHTS. The launcher returns one ASCII disposition packet, with NUL and the complete
response body appended for Ok. Its exit code indicates driver-level success.
Only --self-test uses the built-in Python peer. It grades the apparatus itself.
"""
import argparse
import contextlib
import fcntl
import hashlib
import http.client
import http.server
import json
import os
from pathlib import Path
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
        self.release = threading.Event()
        self.lock = threading.Lock()
        super().__init__(address, handler)

    def get_request(self):
        sock, peer = super().get_request()
        sock.settimeout(4)
        self.connections += 1  # independent TCP accept, before TLS
        return sock, peer

    def handle_error(self, *_):
        self.valid = False  # avoid logging peer-controlled data


class Proxy(socketserver.BaseRequestHandler):
    def handle(self):
        pass  # TCP accept alone is a failure on the proxy-env arm


class Endpoint(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
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
        if case in ('stall', 'lost-reply'):
            if case == 'stall':
                self.server.release.wait(8)
            self.close_connection = True
            return
        self.send_response_only(307 if case == 'redirect' else 200)
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


def drive(root, command, case, proxy, endpoint):
    deadline = now_ms() + (1800 if case == 'stall' else 7000)
    packet = FRAME.pack(b'WBT1', RID, 1, 2, deadline)
    with contextlib.ExitStack() as stack:
        parent, child = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        stack.enter_context(parent)
        stack.enter_context(child)
        fd = os.memfd_create('fixture-token', os.MFD_ALLOW_SEALING | os.MFD_CLOEXEC)
        stack.callback(os.close, fd)
        os.write(fd, endpoint.token.encode())
        os.lseek(fd, 0, os.SEEK_SET)
        fcntl.fcntl(fd, fcntl.F_ADD_SEALS, fcntl.F_SEAL_SEAL | fcntl.F_SEAL_WRITE |
                    fcntl.F_SEAL_GROW | fcntl.F_SEAL_SHRINK)
        env = dict(PATH=os.defpath, WB_ISSUER_FD=str(child.fileno()), WB_CREDENTIAL_FD=str(fd))
        if case == 'proxy-env':
            url = 'http://127.0.0.1:' + str(proxy.server_address[1])
            env.update(https_proxy=url, HTTPS_PROXY=url, ALL_PROXY=url)
        parent.sendall(packet)
        if case == 'pre-cancel':
            parent.sendall(b'C')
        if case == 'duplicate':
            parent.sendall(packet)
        p = subprocess.Popen(command, cwd=root, env=env, pass_fds=(child.fileno(),fd),
                             user=65534, group=65534, extra_groups=[], start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        child.close()
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
                with socket.create_connection(TARGET, timeout=1) as tcp:
                    socket.send_fds(parent, [b'S'], [tcp.fileno()])
            if msg.startswith(b'Ok\0') and msg[3:] == endpoint.reply:
                msg = b'Ok'
            elif msg == b'Ok':
                raise ValueError('missing response body')
            if msg not in {v.encode() for v in CASES.values()}:
                raise ValueError('unknown disposition')
            if case == 'stall' and now_ms() < deadline:
                raise ValueError('premature deadline disposition')
            if p.wait(timeout=2) != 0:
                raise ValueError('driver exit')
            return msg.decode()
        finally:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(p.pid, signal.SIGKILL)
            p.wait()


def exercise(root, command, tls, case, mutant=False):
    endpoint = Observer(TARGET, Endpoint)
    endpoint.tls, endpoint.case, endpoint.token = tls, case, secrets.token_hex(24)
    endpoint.attempts = 0
    proposal = dict(schema_version=1, request_id=RID.decode(), action='create_marker',
                    expected_effect='marker_contains_payload', payload_b64='YWJj')
    message = dict(role='assistant', content=json.dumps(proposal))
    endpoint.reply = json.dumps(dict(object='chat.completion', model=MODEL, id=secrets.token_hex(12),
                                     choices=[dict(index=0, finish_reason='stop', message=message)])).encode()
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
    want = int(case != 'pre-cancel')
    passed = (result == CASES[case] and endpoint.attempts == endpoint.connections == endpoint.requests == want
              and endpoint.valid and proxy_attempts == 0)
    if mutant:
        passed = not passed and endpoint.valid and result == 'Ok' and endpoint.attempts == endpoint.connections == 1 and endpoint.requests == 2
    return dict(case='detect-double-send' if mutant else case, passed=passed, disposition=result,
                connector_attempts=endpoint.attempts, connections=endpoint.connections, requests=endpoint.requests,
                proxy_connections=proxy_attempts, request_shape_valid=endpoint.valid)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--driver', type=Path, help='fixture launcher executable implementing the inherited-FD interface')
    mode.add_argument('--self-test', action='store_true')
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
        root.chmod(0o755)
        cert.chmod(0o644)
        dest = root/'driver'
        shutil.copyfile(args.driver if args.driver else script,dest)
        dest.chmod(0o555)
        command = [str(dest)] if args.driver else [sys.executable,str(dest),'--peer']
        success = True
        for case in [*CASES, *(['mutant'] if args.self_test else [])]:
            try:
                row = exercise(root, command+(['--double'] if case=='mutant' else []), tls,
                               'success' if case=='mutant' else case, case=='mutant')
            except (OSError, ValueError, subprocess.SubprocessError) as exc:
                row = dict(case=case,passed=False,error=type(exc).__name__)
            print(json.dumps(dict(subject='oracle-self-test' if args.self_test else 'external-driver',**row)),flush=True)
            success &= row['passed']
        return int(not success)


if __name__ == '__main__':
    if sys.argv[1:2] == ['--peer']:
        self_test_peer(sys.argv[2:] == ['--double'])
    else:
        sys.exit(main())
