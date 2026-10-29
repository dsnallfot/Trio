#!/usr/bin/env python3
"""Offline JSCore replay of Trio's actual bundled algorithms (macOS + Xcode).

Default mode only verifies; --record writes NEW golden files and never overwrites.
Fixtures are synthetic. Golden outputs record current behavior, not clinical correctness.
"""
import argparse
import copy
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
MODULES = ('profile', 'autosens', 'meal', 'iob', 'determineBasal')


def difference(expected, actual, path='$'):
    if type(expected) is not type(actual):
        # JSON numbers can be emitted as integer or floating point by different encoders.
        if type(expected) in (int, float) and type(actual) in (int, float) and expected == actual:
            return None
        return f'{path}: type/value {expected!r} != {actual!r}'
    if isinstance(expected, dict):
        if expected.keys() != actual.keys():
            return f'{path}: keys differ: {sorted(expected.keys() ^ actual.keys())}'
        for key in expected:
            mismatch = difference(expected[key], actual[key], f'{path}.{key}')
            if mismatch:
                return mismatch
    elif isinstance(expected, list):
        if len(expected) != len(actual):
            return f'{path}: lengths {len(expected)} != {len(actual)}'
        for index, (a, b) in enumerate(zip(expected, actual)):
            mismatch = difference(a, b, f'{path}[{index}]')
            if mismatch:
                return mismatch
    elif expected != actual:
        return f'{path}: {expected!r} != {actual!r}'
    return None


def check(expected, actual, name):
    mismatch = difference(expected, actual)
    if mismatch:
        raise AssertionError(f'{name}: {mismatch}')


def arguments(fixture, results, module):
    f = fixture
    if module == 'profile':
        return [f['pumpSettings'], f['targets'], f['isf'], f['basal'], f['preferences'],
                f['carbRatio'], f['tempTargets'], f['model'], None, f['trioSettings']]
    profile = results['profile']
    if module == 'autosens':
        return [f['glucose'], f['history'], f['basal'], profile, f['carbs'], f['tempTargets']]
    if module == 'meal':
        return [f['history'], profile, f['clock'], f['glucose'], f['basal'], f['carbs']]
    if module == 'iob':
        return [f['history'], profile, f['clock'], results['autosens']]
    return [results['iob'], f['currentTemp'], f['glucose'], profile, results['autosens'],
            results['meal'], f['microBolusAllowed'], f['reservoir'], f['clock'],
            f['history'], f['preferences'], f['basal'], f['oref2']]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=HERE.parent)
    parser.add_argument('--fixtures', type=Path, default=HERE.parent / 'TrioTests/OrefReplay/fixtures')
    parser.add_argument('--record', action='store_true')
    opts = parser.parse_args()
    root = opts.root.resolve()
    baseline = json.loads((root / 'docs/swift-oref-baseline.json').read_text())
    sources = {p: h for p, h in baseline['sha256'].items() if p.startswith('Trio/Resources/javascript/')}
    for path, sha in sources.items():
        check(sha, hashlib.sha256((root / path).read_bytes()).hexdigest(), path)
    cases = sorted(opts.fixtures.glob('*.input.json'))
    if not cases:
        raise AssertionError('No fixtures found')
    # Guard the comparison mechanism against the failure modes it must catch.
    assert difference({'units': 0.1}, {'units': 0.2})
    assert difference({'units': None}, {})
    assert difference({'predBGs': [100, 99]}, {'predBGs': [100, 98]})
    assert difference(False, 0)
    assert difference(0.1, 0.10000000001)
    assert difference({'a': 1, 'b': None}, {'b': None, 'a': 1.0}) is None

    with tempfile.TemporaryDirectory(prefix='trio-oref-replay-') as temp:
        binary = Path(temp) / 'oref-replay'
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', temp + '/modules',
                        str(HERE / 'oref-replay/main.swift'), '-o', str(binary)], check=True)

        def invoke(fixture, module, args):
            request = {key: fixture[key] for key in ('clock', 'timezoneOffsetMinutes')}
            request.update(module=module, arguments=args)
            result = subprocess.run([str(binary), str(root)], input=json.dumps(request, allow_nan=False),
                                    text=True, capture_output=True, timeout=60,
                                    env={**os.environ, 'TZ': fixture['timezone']})
            if result.returncode:
                raise AssertionError(f'{fixture["name"]}/{module}: {result.stderr}')
            return json.loads(result.stdout)

        calls = 0
        for path in cases:
            fixture = json.loads(path.read_text())
            golden_path = path.with_name(path.name.replace('.input.json', '.expected.json'))
            if opts.record and golden_path.exists():
                raise AssertionError(f'Refusing to overwrite {golden_path}')
            expected = None if opts.record else json.loads(golden_path.read_text())
            if expected:
                check(expected['inputSha256'], hashlib.sha256(path.read_bytes()).hexdigest(), str(path))
                check(expected['sourceSha256'], sources, 'JS version')
            results, recorded = {}, {}
            for module in MODULES:
                args = arguments(fixture, results, module)
                result = invoke(fixture, module, args)
                calls += 1
                if expected:
                    check(expected['modules'][module]['output'], result, fixture['name'] + '/chain/' + module)
                    # Isolated replay uses the saved inputs, independent of earlier stages.
                    isolated = invoke(fixture, module, expected['modules'][module]['arguments'])
                    calls += 1
                    check(expected['modules'][module]['output'], isolated, fixture['name'] + '/isolated/' + module)
                else:
                    check(result, invoke(fixture, module, args), fixture['name'] + '/repeat/' + module)
                    calls += 1
                results[module] = result
                recorded[module] = {'arguments': args, 'output': result}
            if 'error' in results['profile']:
                raise AssertionError('Invalid profile fixture')
            if not isinstance(results['iob'], list) or not results['iob']:
                raise AssertionError('Missing IOB forecast')
            determination = results['determineBasal']
            if 'error' in determination or 'reason' not in determination:
                raise AssertionError(f'Invalid determination fixture: {determination}')
            # Scenario-specific independent assertions supplement golden comparisons.
            for key, value in fixture.get('expectDetermination', {}).items():
                check(value, determination.get(key), fixture['name'] + '/' + key)
            if opts.record:
                golden = {'baselineCommit': baseline['baseline_commit'],
                          'inputSha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                          'sourceSha256': sources, 'modules': recorded}
                golden_path.write_text(json.dumps(golden, indent=2, ensure_ascii=False, allow_nan=False) + '\n')
            print(f'PASS {fixture["name"]}: profile/autosens/meal/iob/determineBasal')

        # Prove the existing local SMB fix is covered by executing a reverted copy.
        smb = json.loads((opts.fixtures.parent / 'smb-low-temp.json').read_text())
        request = smb['request']
        smb_fixture = {**request, 'timezone': smb['timezone'], 'name': 'smb-low-temp'}
        actual = invoke(smb_fixture, request['module'], request['arguments'])
        for key, value in smb['expected'].items():
            check(value, actual.get(key), 'smb-low-temp/' + key)
        mutant_root = Path(temp) / 'reverted-smb'
        shutil.copytree(root / 'Trio/Resources/javascript', mutant_root / 'Trio/Resources/javascript')
        bundle = mutant_root / 'Trio/Resources/javascript/bundle/determine-basal.js'
        code = bundle.read_text()
        fixed = 'n(Je*(30-Ar)/30,2)'
        if code.count(fixed) != 1:
            raise AssertionError('Pinned local SMB correction not found exactly once in bundle')
        bundle.write_text(code.replace(fixed, 'n(Je*Ar/30,2)'))
        bad = subprocess.run([str(binary), str(mutant_root)], input=json.dumps(request), text=True,
                             capture_output=True, check=True, timeout=60,
                             env={**os.environ, 'TZ': smb['timezone']})
        reverted = json.loads(bad.stdout)
        check(smb['incorrectRateBeforeFix'], reverted['rate'], 'reverted SMB rate')
        assert difference(actual['rate'], reverted['rate']), 'SMB mutation escaped detection'
        print('PASS SMB regression: corrected 0.9 U/h; reverted copy 0.1 U/h (30m, SMB 0.1 U)')

        # Deliberate timezone mismatch must fail; otherwise replay is not reproducible.
        invalid = copy.deepcopy(fixture)
        invalid['timezoneOffsetMinutes'] += 1
        try:
            invoke(invalid, 'profile', arguments(invalid, {}, 'profile'))
        except AssertionError as error:
            assert 'timezone mismatch' in str(error), str(error)
        else:
            raise AssertionError('Timezone mismatch was not detected')
        print(f'PASS {len(cases)} scenarios, {calls} algorithm invocations; exact JSON comparisons, frozen Date and timezone guards')


if __name__ == '__main__':
    main()
