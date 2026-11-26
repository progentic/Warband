"""Seal or independently regrade the offline Phase 4 negative-path evidence."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from run_odin_tests import ROOT, execute_package, read_manifest, validate_report

sys.path.insert(0, str(ROOT/'tests/integration/linux'))
from test_workflow_admission import REVIEW_CASES, clean_output
from test_provider_transport import fixture_body


def records(path):
    return [json.loads(s) for s in path.read_text().splitlines() if s.startswith('{')]


def codec_packages():
    return [p for p in read_manifest(ROOT/'tests/odin-packages.json') if p.path in ('tests/odin/audit','tests/odin/timing')]


def grade(evidence):
    tests = {}
    for pkg in codec_packages():
        name = Path(pkg.path).name
        report = json.loads((evidence/'codecs'/f'{name}.json').read_text())
        validate_report(pkg, report)
        tests[name] = pkg.names
    assert 'marker_approval_withholds_on_mutation' in tests['audit'] and 'marker_linked_golden_records' in tests['audit']
    assert 'deadline_boundaries_are_strict' in tests['timing']
    cases = records(evidence/'cases.jsonl')
    legacy = {(r['case'],r['catalog']):r for r in cases if 'case' in r}
    baseline = [(c,2) for c in (*REVIEW_CASES,'control','duplicate','wrong-id','wrong-example','wrong-length','expired')]
    assert set(legacy)==set(baseline+[('control',1),('approve',1)]) and sum('case' in r for r in cases)==20
    fixtures = {r['fixture']:r for r in cases if 'fixture' in r}
    rejected = {'bad-content':'Candidate.InvalidJson', 'unknown-action':'Candidate.WrongAction',
                'target-path':'Candidate.UnknownKey', 'schema-two':'Candidate.UnsupportedSchemaVersion',
                'substitute-bytes':'Candidate.PayloadMismatch', 'success-only':'Candidate.UnknownKey',
                'tool-secret':'Envelope.ToolOutput', 'tool-result':'Envelope.InvalidEnvelope', 'error-secret':'HttpFailure',
                'replay-reply':'Candidate.RequestIdMismatch', 'promote-action':'Candidate.WrongAction'}
    valid = {'assert-success','audit-tamper','success','promotion-followup'}
    assert set(fixtures)==set(rejected)|valid and sum('fixture' in r for r in cases)==len(fixtures)
    assert len({r['request_id'] for r in fixtures.values()})==len(fixtures)
    for case, r in fixtures.items():
        body = fixture_body(r['request_id'].encode(), {1:'',2:'YWJj'}[r['catalog']])
        assert r['sent_sha256']==hashlib.sha256(body).hexdigest() and r['exact_body'] and r['requests']==1
        assert r['selection'] == (case in valid) and r['disposition']==rejected.get(case,'Ok')
        if case in rejected or case=='success':
            assert r['consumptions']==0 and r['kinds']==([18,19]*2 if case=='replay-reply' else [18,19])
    stale, held = fixtures['replay-reply'], fixtures['success']
    assert stale['reply_sha256']==stale['prior_sha256']==held['reply_sha256']
    promotion, fresh = fixtures['promote-action'],fixtures['promotion-followup']
    assert promotion['catalog']==1 and fresh['catalog']==2 and fresh['prior_sha256']==promotion['reply_sha256']
    assert fresh['review']=='Permitted' and fresh['kinds']==[18,19,18,1,11,12,13] and fresh['consumptions']==1
    admitted = fixtures['assert-success']
    assert admitted['kinds']==[18,1,11] and admitted['consumptions']==1 and len(admitted['fingerprint'])==64
    tamper = fixtures['audit-tamper']
    assert (tamper['chain'],tamper['review'],tamper['display'],tamper['kinds'])==('mismatch','ReconciliationRequired',False,[18,1,11])
    assert legacy['duplicate',2]['redelivery']=='Consumed' and legacy['duplicate',2]['duplicate_new_admissions']==0
    for case in ('ref','fingerprint','length','digest'):
        assert legacy[case,2]['outcome']=='BindingMismatch' and legacy[case,2]['permits']==0
    dispatch = {r['marker_dispatch']:r for r in records(evidence/'dispatch.jsonl') if 'marker_dispatch' in r}
    assert dispatch['ordinary']['gate']=='Eligible' and dispatch['ordinary']['handoffs']==1
    changed = dispatch['payload']
    assert changed['gate']=='PayloadMismatch' and changed['handoffs']==0 and changed['comparison_reason']==9
    assert changed['advertised_payload_digest']!=changed['offered_payload_digest']
    assert changed['worker_invocations']==0
    launches = subprocess.check_output([sys.executable,ROOT/'tests/integration/linux/test_workflow_admission.py',
                                        '--grade-launches',evidence], text=True)
    assert json.loads(launches)==json.loads((evidence/'launches.json').read_text())==dict(graded_reviews=13,worker_launches=0)

    rows = {}
    def row(number, measured, remaining='Live-path exit evidence.'):
        rows[f'WB-NEG-{number:03}'] = dict(offline=measured, remaining=remaining)
    row(1, 'Malformed content in a valid provider envelope rejected before selection and intake.')
    row(2, 'Unregistered action and unsolicited tool output rejected at candidate and envelope boundaries.')
    row(3, 'Caller-selected target path rejected before intake.', 'External destination denial separately qualified in 3c/3d; live evidence owed.')
    row(4, 'Named timing suite exercised the capability deadline below, at and above expiry.',
        'Model-origin permit expiry at dispatch. Issuance expiry receives no capability credit.')
    row(5, 'Duplicate selection returned Consumed with one original admission pair.',
        'Execution and acceptance replay are separately qualified on the Phase 3 path; model-origin execution remains open.')
    row(6, 'Actual reply from an earlier issuance rejected under the fresh ID; neither delivery consumed.',
        'Stale execution results remain a separate downstream obligation.')
    row(7, 'A success-only reply was rejected. Metadata claiming success accompanied one valid proposal at 1/0 with no completion events.')
    row(8, dict(provider='Same-length abd substitution rejected by payload comparison before admission.',
                admission='The valid abc control supplied catalog bytes; the confirmed fingerprint equalled the catalog-derived expectation.',
                approval='Changed approval packet withheld permits. Audit fixture rejects same-length mutation against existing approval.',
                dispatch='Phase 3 post-claim fixture rerun: changed offered payload withheld handoff and recorded refusal.',
                control_fingerprint=admitted['fingerprint']), 'Model-origin post-claim dispatch remains open.')
    row(9, 'A changed persisted kind-11 payload disagreed with the custody head. Review reconciled before display and preserved the altered row.')
    row(10, 'The canonical kind-11 audit decoder accepted the linked control and rejected a cleared recovery byte at offset 181.',
        'Model JSON has no recovery field. Model-origin dispatch with invalid recovery remains open.')
    row(11, 'Secret-bearing tool output and HTTP error yielded typed dispositions. Request bodies matched the closed projection; durable bytes and retained artifacts passed the canary scan.',
        'Custody-backed provider failure audit and downstream tool-output coverage remain open.')
    row(12, 'Candidate schema version 2 rejected by the common validator before intake.')
    return dict(negative=rows, learned_promotion=dict(rules=['WB-CON-010','WB-INV-010'],
                first=promotion['request_id'],next=fresh['request_id'],fresh_request_sha256=fresh['sent_sha256'],
                outcome='Rejected; original reply excluded from exact fresh projection; authenticated approval required.'),
                boundary='Offline synthetic TLS on preproduction x64-review. Live provider and Phase 4 exit remain pending.')


def inventory(directory):
    result = {}
    for path in sorted(directory.rglob('*')):
        if path.is_symlink(): raise ValueError('unexpected evidence symlink')
        if path.is_file() and path!=directory/'negative-manifest.json':
            data=path.read_bytes()
            clean_output(data)
            result[str(path.relative_to(directory))]=hashlib.sha256(data).hexdigest()
    return result


def main(args):
    if not __debug__ or len(args)<2: raise ValueError('qualification requires assertions, mode and evidence path')
    mode, directory = args[0],Path(args[1]).resolve(strict=True)
    manifest = directory/'negative-manifest.json'
    if mode=='--codecs' and len(args)==2:
        for pkg in codec_packages():
            execute_package(ROOT/'.local/toolchains/odin-linux_amd64/odin',directory/'codecs',pkg)
        return
    if mode=='--verify' and len(args)==3:
        assert hashlib.sha256(manifest.read_bytes()).hexdigest()==args[2], 'manifest hash mismatch'
        report=json.loads(manifest.read_text())
        assert report['files']==inventory(directory) and report['coverage']==grade(directory)
    elif mode=='--seal' and len(args)==3:
        assert len(args[2])==40 and all(c in '0123456789abcdef' for c in args[2])
        report=dict(tree=args[2], kernel='6.8.0-142-generic', coverage=grade(directory), files=inventory(directory))
        with manifest.open('x') as stream: json.dump(report,stream,sort_keys=True,indent=2)
    else: raise ValueError('expected --codecs, --seal TREE or --verify MANIFEST_SHA256')
    print(json.dumps(dict(tree=report['tree'], manifest_sha256=hashlib.sha256(manifest.read_bytes()).hexdigest(),
                          negative_rows=len(report['coverage']['negative']), learned_promotion='rejected')))


if __name__=='__main__':
    main(sys.argv[1:])
