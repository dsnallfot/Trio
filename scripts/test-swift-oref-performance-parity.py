#!/usr/bin/env python3
"""Record local Swift pipeline outputs, then compare optimized Swift against them.
Only the determination UUID is normalized; reason strings and all numeric fields remain exact.
"""
import argparse, hashlib, importlib.util, json, os, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def extended_fixtures():
    import copy
    base=json.load(open(ROOT/'TrioTests/OrefReplay/fixtures/meal-smb.input.json'))
    cases=[]
    for name,oref,prefs,extra in [
     ('override-isf-cr',{'useOverride':True,'overridePercentage':150,'isfAndCr':True},{},{}),
     ('override-isf',{'useOverride':True,'overridePercentage':130,'isf':True},{},{}),
     ('override-cr',{'useOverride':True,'overridePercentage':80,'cr':True},{},{}),
     ('override-target',{'useOverride':True,'overrideTarget':120},{},{}),
     ('override-smb-limits',{'useOverride':True,'advancedSettings':True,'smbMinutes':17,'uamMinutes':13},{},{}),
     ('smb-day-off',{'smbIsScheduledOff':True,'start':10,'end':13},{},{}),
     ('smb-night-on',{'smbIsScheduledOff':True,'start':22,'end':6},{},{}),
     ('smb-all-off',{'smbIsScheduledOff':True,'start':0,'end':0},{},{}),
     ('dynamic-high-target',{'useOverride':True,'overrideTarget':125},{'useNewFormula':True,'high_temptarget_raises_sensitivity':True},{}),
     ('dynamic-short-history',{}, {'useNewFormula':True}, {'history':base['history'][:10]}),
     ('dynamic-no-history',{}, {'useNewFormula':True}, {'history':[]}),
     ('exercise-target',{}, {'exercise_mode':True}, {'tempTargets':[{'_id':'synthetic-target','created_at':'2026-02-12T10:50:00Z','duration':60,'targetTop':140,'targetBottom':140,'enabled':True}]}),
     ('low-target',{}, {'low_temptarget_lowers_sensitivity':True}, {'tempTargets':[{'_id':'synthetic-target','created_at':'2026-02-12T10:50:00Z','duration':60,'targetTop':80,'targetBottom':80,'enabled':True}]})]:
     f=copy.deepcopy(base);f['name']=name;f['oref2'].update(oref);f['preferences'].update(prefs);f.update(extra);cases.append(f)
    return cases

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--binary', type=Path, required=True)
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--record', action='store_true')
    p.add_argument('--extended-only', action='store_true')
    p.add_argument('--report', type=Path)
    o = p.parse_args()
    spec = importlib.util.spec_from_file_location('replay', ROOT/'scripts/test-oref-replay.py')
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    def invoke(request, timezone):
        result = subprocess.run([str(o.binary)], input=json.dumps(request), text=True, capture_output=True,
                                env={**os.environ, 'TZ': timezone}, timeout=120)
        if result.returncode: raise RuntimeError(result.stderr)
        output = json.loads(result.stdout)
        if request['module'] == 'determineBasal' and isinstance(output, dict): output.pop('id', None)
        return output
    if o.record:
        assert not o.baseline.exists(), 'Never overwrite the frozen pre-optimization baseline'
        rows = []
        for path in ([] if o.extended_only else sorted((ROOT/'TrioTests/OrefReplay/fixtures').glob('*.input.json'))):
            fixture = json.loads(path.read_text())
            golden = json.loads(path.with_name(path.name.replace('.input', '.expected')).read_text())
            for mode in ['isolated', 'chain']:
                outputs = {}
                for module in helper.MODULES:
                    args = golden['modules'][module]['arguments'] if mode == 'isolated' else helper.arguments(fixture, outputs, module)
                    request = {'clock': fixture['clock'], 'module': module, 'arguments': [json.dumps(a) for a in args]}
                    output = invoke(request, fixture['timezone']); outputs[module] = output
                    rows.append({'case': fixture['name'], 'mode': mode, 'timezone': fixture['timezone'], 'request': request, 'output': output})
        if o.extended_only:
            for fixture in extended_fixtures():
                outputs = {}
                for module in helper.MODULES:
                    args = helper.arguments(fixture, outputs, module)
                    request = {'clock': fixture['clock'], 'module': module, 'arguments': [json.dumps(a) for a in args]}
                    output = invoke(request, fixture['timezone']); outputs[module] = output
                    rows.append({'case': fixture['name'], 'mode': 'chain', 'timezone': fixture['timezone'], 'request': request, 'output': output})
        smb = json.loads((ROOT/'TrioTests/OrefReplay/smb-low-temp.json').read_text())
        request = {**smb['request'], 'arguments': [json.dumps(a) for a in smb['request']['arguments']]}
        rows.append({'case': 'local-smb-low-temp', 'mode': 'isolated', 'timezone': smb['timezone'], 'request': request, 'output': invoke(request, smb['timezone'])})
        hashes = {str(f.relative_to(ROOT)): hashlib.sha256(f.read_bytes()).hexdigest() for f in (ROOT/'Trio/Sources/APS/OpenAPSSwift').rglob('*.swift')}
        o.baseline.write_text(json.dumps({'sourceSha256': hashes, 'cases': rows}, ensure_ascii=False, indent=2)+'\n')
        print(f'Recorded {len(rows)} local Swift outputs including complete reason strings')
    else:
        rows = json.loads(o.baseline.read_text())['cases']; failures = []
        for row in rows:
            actual = invoke(row['request'], row['timezone'])
            if actual != row['output']: failures.append({**row, 'actual': actual})
        report = {'comparisons': len(rows), 'failures': failures, 'passed': not failures}
        if o.report: o.report.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
        print(f'{len(rows)-len(failures)}/{len(rows)} exact local Swift comparisons passed')
        if failures: raise SystemExit(1)
if __name__ == '__main__': main()
