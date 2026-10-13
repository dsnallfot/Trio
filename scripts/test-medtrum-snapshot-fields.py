#!/usr/bin/env python3
"""Fail if a new persisted key is omitted from the typed snapshot contract."""
from pathlib import Path
import re
r = Path(__file__).resolve().parents[1] / 'MedtrumKit'
state = (r / 'MedtrumKit/PumpManager/MedtrumPumpState.swift').read_text()
snapshot = (r / 'MedtrumKit/PumpManager/PumpStateSnapshot.swift').read_text()
keys = set(re.findall(r'value\["(\w+)"\] =', state.split('public var rawValue: RawValue {', 1)[1].split('return value', 1)[0]))
fields = set(re.findall(r'let (\w+):', snapshot.split('private struct PersistedPumpSnapshot:', 1)[1].split('struct PumpStateSnapshot:', 1)[0]))
assert not keys - fields, f'Missing persisted fields: {keys - fields}'
dose = (r / 'Common/UnfinalizedDose.swift').read_text()
dosekeys = set(re.findall(r'raw\["(\w+)"\] =', dose.split('public var rawValue: RawValue {', 1)[1].split('return raw', 1)[0]))
dosefields = set(re.findall(r'let (\w+):', snapshot.split('struct DoseSnapshot:', 1)[1].split('init(_ dose:', 1)[0]))
assert dosekeys == dosefields, (dosekeys, dosefields)
assert 'state.rawValue' not in snapshot and 'NSDictionary' not in snapshot
print(f'PASS: all {len(keys)} persisted keys and {len(dosekeys)} dose keys covered; no raw serialization in snapshot')
