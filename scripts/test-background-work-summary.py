#!/usr/bin/env python3
"""Exercise the production task observer with a fake UIKit ID and deterministic time."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
code = (root / 'Trio/Sources/APS/FetchGlucoseManager.swift').read_text().split('final class BackgroundTaskDiagnostics:', 1)[1]
prelude = '''import Foundation
struct UIBackgroundTaskIdentifier: Hashable {
    let rawValue: Int
    static let invalid = Self(rawValue: -1)
}
enum DiagnosticLogging {
    static var isEnabled = true
    static var detailEnabled = false
}
enum LogCategory { case deviceManager }
var lines: [String] = []
func debug(_ category: LogCategory, _ message: String) { lines.append(message) }
'''
test = r'''
let d = BackgroundTaskDiagnostics(startTime: 0)
let a = UIBackgroundTaskIdentifier(rawValue: 1)
let b = UIBackgroundTaskIdentifier(rawValue: 2)
d.record(.start, id: a, name: "loop", now: 1)
d.record(.start, id: b, name: "upload", now: 2)
d.record(.end, id: b, name: "upload", now: 5)
precondition(lines.isEmpty)
d.record(.end, id: a, name: "loop", now: 901)
precondition(lines.count == 1)
precondition(lines[0].contains("BGTaskSummary") && lines[0].contains("loop.start=1"))
precondition(lines[0].contains("upload.end=1") && lines[0].contains("trackedOpen=0"))
precondition(lines[0].contains("maxCompletedMs=900000") && lines[0].contains("peakOpen=2"))
d.record(.start, id: a, name: "loop", now: 902)
d.record(.start, id: a, name: "loop", now: 903)
precondition(lines.last!.contains("already-open"))
d.record(.expiration, id: a, name: "loop", now: 904)
precondition(lines.last!.contains("event=expiration"))
d.record(.end, id: a, name: "loop", now: 905)
precondition(lines.count == 3) // Ordinary completion remains quiet.
d.record(.end, id: b, name: "upload", now: 906)
precondition(lines.last!.contains("untracked-id"))
d.record(.start, id: .invalid, name: "loop", now: 907)
precondition(lines.last!.contains("invalid-id"))
DiagnosticLogging.detailEnabled = true
d.record(.start, id: b, name: "upload", now: 908)
precondition(lines.last!.contains("event=start"))
DiagnosticLogging.detailEnabled = false
d.record(.end, id: b, name: "upload", now: 1801)
precondition(lines.last!.contains("windowSec=900") && lines.last!.contains("trackedOpen=0"))
precondition(lines.last!.contains("upload.end=2") && !lines.last!.contains("maxCompletedMs=900000"))
print("PASS: quiet ordinary tasks, 15-minute summaries, duration/peak/reset, immediate anomalies, detail opt-in")
'''
with tempfile.TemporaryDirectory(prefix='trio-work-summary-') as d:
    p = Path(d) / 'main.swift'
    p.write_text(prelude + '\nfinal class BackgroundTaskDiagnostics:' + code + test)
    subprocess.run(['swift', '-module-cache-path', '/tmp/trio-swift-cache', str(p)], check=True)
