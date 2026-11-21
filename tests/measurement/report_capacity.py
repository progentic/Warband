"""Summarize a completed capacity.py capture. Missing stores fail the inventory check."""
import gzip
import json
import sys
from collections import Counter, defaultdict

groups = defaultdict(list)
with gzip.open(sys.argv[1],'rt') as stream:
    for line in stream:
        row = json.loads(line)
        groups[row['total'],row['rep']].append(row)
assert set(groups) == {(1,1)} | {(t,r) for t in (100,1000,10000) for r in (1,2,3)}

for (total,rep),rows in sorted(groups.items()):
    n = min(total,50)
    assert [r['segment'] for r in rows] == list(range(total//n))
    assert all(r['n']==n for r in rows)
    phases = defaultdict(Counter)
    storage = Counter()
    for r in rows:
        a,b,c = (r[p] for p in ('A','B','C'))
        assert a['head']==b['head'] and a['counts']==b['counts']==[0,0] and a['mark']==b['mark']==0
        tips = [r[p]['server'][0][1] for p in ('baseline','imported','noop')]
        assert tips==[1,n+1,3*n+1] and all(r[p]['server'][0][0]==3 for p in ('baseline','imported','noop'))
        assert c['counts']==[n,n] and c['mark']==n+1 and r['imported']['client'][-1]<80000
        for phase in ('baseline','imported','noop','denials'):
            server = r[phase] if phase=='denials' else r[phase]['server']
            for op,history,selection,embedded in server:
                for stage,value in zip(('history','selection','reply'),(history,selection,embedded)):
                    phases[phase][f'custodian.{op}.{stage}'] += value
            if phase!='denials':
                for stage,value in zip(('reply','receipt','prefix','predecessor','readback','exchange','charged'),r[phase]['client']):
                    phases[phase][f'importer.{stage}'] += value
        for phase in ('B','C'):
            for component,base,size in zip(('history','database','wal'),r['A']['sizes'],r[phase]['sizes']):
                storage[phase+'.'+component] += (size or 0)-(base or 0)
    imp = phases['imported']
    actual = sum(imp.values())-imp['importer.exchange']-imp['importer.charged']
    assert storage['B.history']==203*total and storage['C.history']==705*total
    print(json.dumps(dict(total=total,rep=rep,per_store=n,stores=len(rows),counts=phases,bytes_delta=storage,
                          visits_per_confirmed=actual/total,charged_over_observed=imp['importer.charged']/actual,
                          endpoint_bytes_per_denial=sum(storage['C.'+c] for c in ('history','database','wal'))/total)))
