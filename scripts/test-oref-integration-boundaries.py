#!/usr/bin/env python3
"""Source-boundary regression guard, not an APNS/network/Shortcuts runtime test."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
baseline = json.loads((root/'docs/swift-oref-baseline.json').read_text())['sha256']
groups = {'APNS/remote': [], 'Shortcuts': [], 'Nightscout': [], 'JavaScript': []}
for path, expected in baseline.items():
    group = ('APNS/remote' if '/RemoteControl/' in path else
             'Shortcuts' if 'Shortcut' in path or '/Intents/' in path else
             'Nightscout' if 'Nightscout' in path else
             'JavaScript' if '/javascript/' in path else None)
    if group:
        actual = hashlib.sha256((root/path).read_bytes()).hexdigest()
        assert actual == expected, f'{group} changed: {path}'
        groups[group].append(path)
for group, paths in groups.items():
    assert paths, f'No baseline coverage for {group}'
    print(f'PASS {group}: {len(paths)} unchanged source files')
# The two entry points both delegate through the guarded OpenAPS transaction.
manager = (root/'Trio/Sources/APS/APSManager.swift').read_text()
assert 'openAPS.determineBasal(currentTemp: await currentTemp, clock: now)' in manager
assert 'openAPS.determineBasal(currentTemp: temp, clock: Date(), carbs: carbs, iob: iob, simulation: true)' in manager
print('PASS APS and simulation entry points retain the common calculation boundary')
