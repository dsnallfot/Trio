#!/usr/bin/env python3
"""Exercise production cancellation with AlarmKit disappearance/error races."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
manager = (root / "Trio/Sources/Services/GlucoseAlarms/MissingDataAlarmManager.swift").read_text()
start = manager.index("    private func cancel(_ id: UUID)")
opening = manager.index("{", start)
depth, end = 1, opening + 1
while depth:
    depth += (manager[end] == "{") - (manager[end] == "}")
    end += 1
method = manager[start:end].replace("private func", "func")

source = r'''
import Foundation
enum Failure: Error { case unavailable }
struct Alarm { let id: UUID }
final class AlarmManager {
    static let shared = AlarmManager()
    var installed: [Alarm] = []
    var reads = 0, cancels = 0, stops = 0
    var failReads: Set<Int> = []
    var failCancel = false, disappearDuringCancel = false
    var alarms: [Alarm] {
        get throws {
            reads += 1
            if failReads.contains(reads) { throw Failure.unavailable }
            return installed
        }
    }
    func cancel(id: UUID) throws {
        cancels += 1
        if disappearDuringCancel { installed.removeAll { $0.id == id } }
        if failCancel { throw Failure.unavailable }
        installed.removeAll { $0.id == id }
    }
    func stop(id: UUID) throws {
        stops += 1
        installed.removeAll { $0.id == id }
    }
    func reset() {
        installed = []; reads = 0; cancels = 0; stops = 0
        failReads = []; failCancel = false; disappearDuringCancel = false
    }
}
enum Category { case service }
final class Harness {
    struct Saved { var retired: Set<UUID> = [] }
    var saved = Saved()
    var errorText: String?
    var writes = 0, warnings = 0
    func persist() { writes += 1 }
    func warning(_ category: Category, _ message: String) { warnings += 1 }
'''
source += method + "\n}\n"
source += r'''
let system = AlarmManager.shared
let id = UUID(), unrelated = UUID()
func setup(present: Bool = true) -> Harness {
    system.reset()
    system.installed = [Alarm(id: unrelated)] + (present ? [Alarm(id: id)] : [])
    let h = Harness()
    h.saved.retired.insert(id)
    return h
}
func removed(_ h: Harness) {
    precondition(!h.saved.retired.contains(id) && h.writes == 1)
    precondition(h.warnings == 0 && h.errorText == nil)
    precondition(system.installed.contains { $0.id == unrelated })
    precondition(system.stops == 0, "Cancellation must not stop then cancel the same alarm")
}
func retained(_ h: Harness) {
    precondition(h.saved.retired.contains(id) && h.writes == 0)
    precondition(h.warnings == 1 && h.errorText != nil)
}
let normal = setup()
normal.cancel(id)
removed(normal)
precondition(system.cancels == 1)

let absent = setup(present: false)
absent.cancel(id)
removed(absent)
precondition(system.cancels == 0)

let raced = setup()
system.failCancel = true; system.disappearDuringCancel = true
raced.cancel(id)
removed(raced)
precondition(system.reads == 2)

let realFailure = setup()
system.failCancel = true
realFailure.cancel(id)
retained(realFailure)
system.failCancel = false
realFailure.errorText = nil; realFailure.warnings = 0
realFailure.cancel(id)
removed(realFailure)

let unknown = setup()
system.failCancel = true; system.failReads = [2]
unknown.cancel(id)
retained(unknown)

let unavailable = setup()
system.failReads = [1, 2]
unavailable.cancel(id)
retained(unavailable)
precondition(system.cancels == 0)

let readRace = setup(present: false)
system.failReads = [1]
readRace.cancel(id)
removed(readRace)
print("PASS: direct cancellation, absent alarm, disappearance race, genuine failure and retry, unavailable enumeration, unrelated alarms preserved")
'''
with tempfile.TemporaryDirectory(prefix="trio-alarm-cancel-") as temporary:
    path = Path(temporary) / "main.swift"
    path.write_text(source)
    subprocess.run(["swift", "-module-cache-path", "/tmp/trio-swift-cache", str(path)], check=True)
