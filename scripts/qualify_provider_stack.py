"""Run package 3d on x64-review: python3 scripts/qualify_provider_stack.py /path/to/Go/verify_test.go."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tests/integration/linux'))
import test_provider_transport as transport
from test_receipt_import import fixture
from run_odin_tests import discover_packages, execute_package, read_manifest, validate_packages

RUNNER = Path(__file__).resolve()
HTTP = 'api.openai.com'
DENIED = ('WB3D_BODY_', 'WB3D_EXCLUDED_', 'WB3D_SECRET_')


def require(condition, diagnostic):
    if not condition:
        raise RuntimeError(diagnostic)


def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def write_json(path, data):
    path.write_text(json.dumps(data, sort_keys=True, indent=2)+'\n')


def capture(args, path, **kwargs):
    with path.open('x') as log:
        subprocess.run(args, check=True, stdout=log, stderr=subprocess.STDOUT, **kwargs)


def tree():
    def git(*args):
        return subprocess.check_output(['git',*args],text=True).strip()
    require(not git('status','--porcelain','--untracked-files=all'), 'qualify a clean checkout')
    extras=git('ls-files','--others','--','src','cmd')
    require(not extras,'unexpected build inputs')
    return dict(commit=git('rev-parse','HEAD'),tree=git('rev-parse','HEAD^{tree}'))


def snapshot(f):
    _,_,checkpoint,pending,tip,_=f.verify()
    rows=f.rows()
    files={str(p.relative_to(f.root)):digest(p) for d in ('journal','data')
           for p in (f.root/d).iterdir() if p.is_file()}
    return dict(checkpoint=checkpoint.hex(),pending=pending.hex(),custody_tip=tip,
                event_count=len(rows[0]),receipt_bindings=len(rows[1]),files=files)


def guarded(executable, evidence, profile, vectors):
    """The guard owns an enrolled store. Only its fixture directory path enters the harness."""
    require(os.geteuid()==0,'authority guard requires the disposable Linux test scope')
    traces=evidence/(profile+'-traces')
    traces.mkdir()
    with fixture() as (f,_,_):
        f.run('Ready')
        before=snapshot(f)
        require(before['event_count']>0 and not before['pending'],'guard store must start confirmed')
        args=['strace','-ff','-o',str(traces/'trace'),'-e','trace=execve,execveat,fork,vfork,clone,clone3,setresuid,connect,openat',
              '/usr/bin/python3','-u','tests/integration/linux/test_provider_transport.py',
              '--assembled','--trusted-launcher',executable]
        if profile=='production':
            args+=['--production-roots','--public-vectors',vectors]
        capture(args,evidence/(profile+'.jsonl'),env=dict(os.environ,WB_GUARD_STORE=str(f.root)))
        after=snapshot(f)
        require(before==after,'provider run changed the guard store or custody history')
        write_json(evidence/(profile+'-state.json'),dict(before=before,after=after))


def results(path, expected, subject):
    records=[]
    for line in path.read_text().splitlines():
        if line.startswith('{'):
            records.append(json.loads(line))
    other=[r.get('subject') for r in records if r.get('subject')!=subject]
    require(other==(['offline-chain'] if set(expected)=={'untrusted'} else []), 'unexpected evidence row')
    by_case={r['case']:r for r in records if r.get('subject')==subject}
    require(set(by_case)==set(expected) and len(by_case)==sum(r.get('subject')==subject for r in records),
            f'{path.name}: case inventory mismatch')
    require(all(r['passed'] is True for r in by_case.values()),f'{path.name}: failed fixture')
    return by_case,records


def grade_processes(directory, cases):
    traces={int(p.suffix[1:]):p for p in directory.glob('trace.*')}
    matched=set()
    dns_total=upstream_total=0
    for name, r in cases.items():
        # Match the winning launcher's actual child to its syscalls, even for a refused call.
        text=traces[r['launcher_pid']].read_text()
        child_ids=re.findall(r'^(?:fork|vfork|clone3?)\(.*\)\s+= (\d+)$',text,re.M)
        connectors=[int(pid) for pid in child_ids if re.search(r'^setresuid\(60003,',traces[int(pid)].read_text(),re.M)]
        require(len(connectors)<=1,f'{name}: multiple connectors')
        calls=[]
        for pid in connectors:
            require(pid not in matched,'connector counted twice')
            matched.add(pid)
            calls+=re.findall(r'^connect\(.*$',traces[pid].read_text(),re.M)
        dns=sum('htons(53)' in s and '"127.0.0.53"' in s for s in calls)
        upstream=sum('htons(443)' in s and '"93.184.216.34"' in s for s in calls)
        require(dns==len(r['dns']) and upstream==r['connections'] and len(calls)==dns+upstream,
                f'{name}: connection trace disagrees with the synthetic endpoints')
        dns_total+=dns
        upstream_total+=upstream
    all_connectors=set()
    allowed={'unshare','python3','openssl','ip','driver'}
    for pid,p in traces.items():
        text=p.read_text()
        if re.search(r'^setresuid\(60003,',text,re.M): all_connectors.add(pid)
        for line in text.splitlines():
            if line.startswith(('execve(','execveat(')):
                path=re.search(r'"([^"]+)"',line)
                require(path and Path(path[1]).name in allowed,'unexpected executable in provider namespace')
            if re.match(r'^setresuid\(6000[123],',line):
                require(not any(re.search(r'"(?:[^"]*/)?(?:journal|endpoints|data)/',call)
                                for call in text.splitlines() if call.startswith('openat(')),
                        'provider role opened a store or custody path')
            if re.match(r'^setresuid\(6000[12],',line):
                require(all('EPERM' in s for s in re.findall(r'^connect\(.*$',text,re.M)),
                        'adapter role connected directly')
    # A losing, preflight-only or restarted launcher may have no connector.
    require(all_connectors==matched,'unaccounted connector process')
    return dict(cases=len(cases),connector_processes=len(matched),dns_connects=dns_total,
                upstream_connects=upstream_total,additional_connects=0,worker_launches=0)


def verify_manifest(evidence, expected_digest):
    manifest=evidence/'manifest.json'
    require(digest(manifest)==expected_digest,'manifest hash mismatch')
    report=json.loads(manifest.read_text())
    actual={}
    for path in evidence.rglob('*'):
        require(not path.is_symlink(),'unexpected evidence symlink')
        if path.is_file() and path!=manifest:
            actual[str(path.relative_to(evidence))]=digest(path)
    require(report['files']==actual,'retained artifact inventory or hash mismatch')
    for profile,summary in report['profiles'].items():
        expected={'untrusted'} if profile=='production' else (
            set(transport.CASES)|set(transport.EXTENDED)|set(transport.ASSEMBLED))-{'wrong-peer','untrusted'}
        cases,_=results(evidence/(profile+'.jsonl'),expected,'external-driver')
        recomputed=grade_processes(evidence/(profile+'-traces'),cases)
        require(all(summary[k]==v for k,v in recomputed.items()),'trace regrade mismatch')
        state=json.loads((evidence/(profile+'-state.json')).read_text())
        require(state['before']==state['after'] and state['before']['event_count']>0,'authority state mismatch')
    require(set(report['profiles'])=={'fixture','production'},'missing trust profile')
    return report


def run(vectors):
    require(__debug__ and not os.environ.get('PYTHONOPTIMIZE'),'qualification requires assertions')
    require(sys.version_info>=(3,11),'Python 3.11+ required')
    require(os.uname().release=='6.8.0-142-generic' and os.uname().machine=='x86_64','wrong qualification target')
    source=tree()
    out=ROOT/'out/linux_amd64/provider'
    out.mkdir(parents=True,exist_ok=True)
    evidence=Path(tempfile.mkdtemp(prefix='aggregate-142.',dir=out))
    print(f'Aggregate evidence: {evidence}',flush=True)
    capture(['bash','scripts/qualify_provider_connector.sh',evidence],evidence/'connector-run.log')
    connector,=evidence.glob('connector-142.*')
    os.environ['LLVM_CONFIG']='/usr/bin/llvm-config-19'
    packages=read_manifest(ROOT/'tests/odin-packages.json')
    validate_packages(packages,discover_packages(ROOT/'tests/odin'))
    model,=(p for p in packages if p.path=='tests/odin/model')
    execute_package(ROOT/'.local/toolchains/odin-linux_amd64/odin',evidence/'odin',model)

    installation=subprocess.check_output(['sudo','mktemp','-d','/run/warband-aggregate.XXXXXXXX'],text=True).strip()
    driver=Path(installation)/'driver'
    profiles={}
    try:
        for profile in ('fixture','production-roots'):
            standalone=out/('transport-'+profile)
            subprocess.run(['sudo','install','-m555',standalone,driver],check=True)
            options=[] if profile=='fixture' else ['--production-roots','--public-vectors',vectors]
            log=evidence/('transport-'+profile+'.jsonl')
            capture(['sudo','python3','tests/integration/linux/test_provider_transport.py','--trusted-launcher',driver,*options],log)
            results(log,{'untrusted'} if options else (set(transport.CASES)|set(transport.EXTENDED))-{'untrusted'},'external-driver')
        for profile,binary in [('fixture','connector'),('production','connector-production-roots')]:
            source_exe=out/('transport-'+binary)
            identity=out/(binary+'-identity.txt')
            require(digest(source_exe) in identity.read_text(),'identity does not match binary')
            shutil.copyfile(identity,evidence/(profile+'-identity.txt'))
            subprocess.run(['sudo','install','-m555',source_exe,driver],check=True)
            installed=subprocess.check_output(['sudo','sha256sum',driver],text=True).split()[0]
            require(installed==digest(source_exe),'installed binary differs')
            capture(['sudo','systemd-run','--quiet','--scope','-p','MemoryMax=256M','-p','MemorySwapMax=0',
                     '/usr/bin/python3',RUNNER,'--guard',driver,evidence,profile,vectors],evidence/(profile+'-guard.log'))
            # Trace files are created by root in the target scope.
            subprocess.run(['sudo','chown','-R',f'{os.getuid()}:{os.getgid()}',evidence/(profile+'-traces')],check=True)
            expected=({'untrusted'} if profile=='production' else
                      (set(transport.CASES)|set(transport.EXTENDED)|set(transport.ASSEMBLED))-{'wrong-peer','untrusted'})
            cases,rows=results(evidence/(profile+'.jsonl'),expected,'external-driver')
            grade=grade_processes(evidence/(profile+'-traces'),cases)
            if profile=='production':
                chain,=(r for r in rows if r.get('subject')=='offline-chain')
                require(chain['production_bundle']=='accepted' and chain['fixture_bundle']=='rejected','trust vector')
            else:
                a,b=cases['empty-example'],cases['fresh-after-reply']
                require(a['request_id']!=b['request_id'] and [a['example'],b['example']]==[1,2],'fresh projection')
            profiles[profile]=dict(binary_sha256=installed,**grade)
    finally:
        subprocess.run(['sudo','rm','-f',driver],check=True)
        subprocess.run(['sudo','rmdir',installation],check=True)

    capture(['sudo','python3','tests/integration/linux/test_provider_transport.py','--self-test'],evidence/'oracle.jsonl')
    results(evidence/'oracle.jsonl',set(transport.CASES)|{'detect-double-send'},'oracle-self-test')
    require(tree()==source,'source changed during qualification')
    outputs={}
    for path in sorted(p for p in evidence.rglob('*') if p.is_file()):
        data=path.read_bytes()
        require(not any(canary.encode() in data for canary in DENIED), 'canary in retained evidence')
        outputs[str(path.relative_to(evidence))]=hashlib.sha256(data).hexdigest()
    kernel=json.loads((connector/'kernel.json').read_text())
    require(kernel['graded']==51 and kernel['additional_attempts']==0 and kernel['filtered_roles']==2,'3c evidence')
    manifest=dict(source=source,kernel=os.uname().release,profiles=profiles,connector=kernel,files=outputs,
                  coverage={'WB-CON-002/010':'closed projection and common validator',
                            'WB-CON-005':'one-shot request and external destination denial',
                            'WB-CON-007':'sanitized fixture dispositions; workflow audit pending',
                            'WB-NEG-003/011':'offline destination and canary fixtures'},
                  live_provider='pending separate authorization')
    write_json(evidence/'manifest.json',manifest)
    fingerprint=digest(evidence/'manifest.json')
    verify_manifest(evidence,fingerprint)
    print(json.dumps(dict(manifest_sha256=fingerprint,profiles=profiles)),flush=True)


if __name__=='__main__':
    os.chdir(ROOT)
    if sys.argv[1:2]==['--guard'] and len(sys.argv)==6:
        guarded(Path(sys.argv[2]),Path(sys.argv[3]),sys.argv[4],Path(sys.argv[5]))
    elif sys.argv[1:2]==['--verify'] and len(sys.argv)==4:
        report=verify_manifest(Path(sys.argv[2]).resolve(strict=True),sys.argv[3])
        print(json.dumps(dict(verified=True,source=report['source'],profiles=report['profiles'])))
    elif len(sys.argv)==2:
        run(Path(sys.argv[1]).resolve(strict=True))
    else:
        raise SystemExit(__doc__)
