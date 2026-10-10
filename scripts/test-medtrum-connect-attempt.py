#!/usr/bin/env python3
"""Exercise PR #206's production waiter lifecycle without a Bluetooth device."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'MedtrumKit/MedtrumKit/PumpManager/ConnectAttempt.swift').read_text()
checks = r'''
enum MedtrumConnectError: Error { case failedToConnectToDevice }
var reports: [String] = []
let attempt = ConnectAttempt({ _ in reports.append("internal") }, patience: .untilResolved)
precondition(attempt.nextDeadline(budget: 15) == nil)
attempt.addCompletion { _ in reports.append("first") }
precondition((attempt.nextDeadline(budget: 15) ?? 0) > 14)
precondition(attempt.takeExpired(budget: 15).isEmpty)
let expired = attempt.takeExpired(budget: 15, now: Date.now.addingTimeInterval(16))
precondition(expired.count == 1)
expired.forEach { $0(.failedToConnectToDevice) }
precondition(reports == ["first"])
precondition(attempt.nextDeadline(budget: 15) == nil)
precondition(attempt.takeExpired(budget: 15, now: Date.distantFuture).isEmpty)
// A new real caller gets its own budget even after an earlier caller timed out.
attempt.addCompletion { _ in reports.append("late") }
precondition((attempt.nextDeadline(budget: 15) ?? 0) > 14)
precondition(attempt.claim())
precondition(!attempt.claim(), "An attempt can report its final result only once")
let remaining = attempt.takeCompletions()
precondition(remaining.count == 2)
remaining.forEach { $0(nil) }
precondition(reports == ["first", "internal", "late"])
precondition(attempt.takeCompletions().isEmpty)
print("ConnectAttempt passed: bounded/unbounded waiters, expiry without terminating connect, new caller budget, single completion")
'''
with tempfile.TemporaryDirectory(prefix='medtrum-connect-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(source + checks)
    subprocess.run(['swift', '-module-cache-path', directory + '/modules', str(path)], check=True)
