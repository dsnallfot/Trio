#!/usr/bin/env python3
"""Run the actual Swift kernel on macOS, then compare synthetic JS replay contracts.

This does not run iOS/Core Data/APNS/Shortcuts UI. Unresolved forecast differences
are reported explicitly; passing dosing contracts is not full algorithm parity.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DOSE_FIELDS = ['units', 'rate', 'duration', 'insulinReq', 'eventualBG', 'TDD', 'insulin',
               'insulinForManualBolus', 'manualBolusErrorString', 'ISF', 'CR', 'current_target',
               'threshold', 'COB', 'IOB', 'carbsReq', 'minDelta', 'expectedDelta', 'minGuardBG', 'minPredBG']
ABSENT = '<absent>'


def differences(expected, actual, path=''):
    if isinstance(expected, dict) and isinstance(actual, dict):
        return sum((differences(expected.get(k, ABSENT), actual.get(k, ABSENT), f'{path}/{k}')
                    for k in sorted(expected.keys() | actual.keys())), [])
    if isinstance(expected, list) and isinstance(actual, list):
        result = [] if len(expected) == len(actual) else [{'path': path + '/length', 'js': len(expected), 'swift': len(actual)}]
        for i, (a, b) in enumerate(zip(expected, actual)):
            result += differences(a, b, f'{path}/{i}')
        return result
    return [] if expected == actual else [{'path': path, 'js': expected, 'swift': actual}]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    opts = parser.parse_args()
    work = opts.work_dir or Path(tempfile.mkdtemp(prefix='trio-oref-native-'))
    work.mkdir(parents=True, exist_ok=True)
    subprocess.run(['python3', str(ROOT/'scripts/oref-native/setup.py'), str(ROOT), str(work)], check=True)
    env = {**os.environ, 'TZ': 'UTC'}
    for command, name in [(['swift', 'test', '--package-path', str(work)], 'unit-tests.log'),
                          (['swift', 'build', '--package-path', str(work), '--product', 'OrefReplay'], 'replay-build.log')]:
        with (work/name).open('w') as log:
            result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f'{command[1]} failed: {work/name}')
    spec = importlib.util.spec_from_file_location('js_replay', ROOT/'scripts/test-oref-replay.py')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    binary = work/'.build/debug/OrefReplay'
    report = {'host': 'macOS standalone; iOS integration not executed', 'cases': [], 'dosingFailures': [],
              'unitTestLog': str(work/'unit-tests.log'), 'sourceSha256': {}}
    for file in (ROOT/'Trio/Sources/APS/OpenAPSSwift').rglob('*.swift'):
        report['sourceSha256'][str(file.relative_to(ROOT))] = hashlib.sha256(file.read_bytes()).hexdigest()

    def invoke(fixture, module, args):
        request = {'clock': fixture['clock'], 'module': module, 'arguments': [json.dumps(a) for a in args]}
        result = subprocess.run([str(binary)], input=json.dumps(request), text=True, capture_output=True,
                                env={**os.environ, 'TZ': fixture['timezone']}, timeout=60)
        if result.returncode:
            raise RuntimeError(f'{module}: {result.stderr}')
        return json.loads(result.stdout)

    for path in sorted((ROOT/'TrioTests/OrefReplay/fixtures').glob('*.input.json')):
        fixture = json.loads(path.read_text())
        golden = json.loads(path.with_name(path.name.replace('.input', '.expected')).read_text())
        assert golden['inputSha256'] == hashlib.sha256(path.read_bytes()).hexdigest()
        for mode in ['isolated', 'chain']:
            outputs = {}
            for module in helper.MODULES:
                args = golden['modules'][module]['arguments'] if mode == 'isolated' else helper.arguments(fixture, outputs, module)
                actual = invoke(fixture, module, args)
                outputs[module] = actual
                expected = golden['modules'][module]['output']
                diffs = differences(expected, actual)
                row = {'case': fixture['name'], 'mode': mode, 'module': module, 'differences': diffs}
                report['cases'].append(row)
                if module == 'determineBasal':
                    failures = differences({k: expected.get(k, ABSENT) for k in DOSE_FIELDS},
                                           {k: actual.get(k, ABSENT) for k in DOSE_FIELDS})
                    if failures:
                        report['dosingFailures'].append({'case': fixture['name'], 'mode': mode, 'differences': failures})
    smb = json.loads((ROOT/'TrioTests/OrefReplay/smb-low-temp.json').read_text())
    actual = invoke({'clock': smb['request']['clock'], 'timezone': smb['timezone']}, 'determineBasal', smb['request']['arguments'])
    report['smbLowTemp'] = {k: actual.get(k) for k in ['rate', 'duration', 'units']}
    assert report['smbLowTemp'] == {'rate': 0.9, 'duration': 30, 'units': 0.1}, report['smbLowTemp']
    report['dosingContractsPassed'] = not report['dosingFailures']
    report['fullJSONParity'] = not any(c['differences'] for c in report['cases'])
    report['forecastDifferences'] = [{'case': c['case'], 'mode': c['mode'], 'differences': [d for d in c['differences'] if d['path'].startswith('/predBGs/')]} for c in report['cases'] if any(d['path'].startswith('/predBGs/') for d in c['differences'])]
    opts.report.parent.mkdir(parents=True, exist_ok=True)
    opts.report.write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n')
    print(f"Swift replay: {len(report['cases'])} module invocations; dosing contracts: {report['dosingContractsPassed']}; full JSON parity: {report['fullJSONParity']}")
    print(f"Forecast differences in {len(report['forecastDifferences'])} comparisons; report: {opts.report}")
    if report['dosingFailures']:
        raise AssertionError(report['dosingFailures'])


if __name__ == '__main__':
    main()
