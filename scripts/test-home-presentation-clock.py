#!/usr/bin/env python3
"""Exercise the production presentation lifecycle method, including queued ticks."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Trio/Sources/Modules/Home/HomeStateModel.swift').read_text()
method = source[source.index('        func setPresentationActive('):source.index('        private func registerObservers()')]
code = '''import Foundation
import Darwin
final class FakeTimer {
    var eventHandler: (() -> Void)?
    var resumes = 0
    var suspends = 0
    func resume() { resumes += 1 }
    func suspend() { suspends += 1 }
}
final class Model {
    let timer = FakeTimer()
    var isPresentationActive = false
    var timerDate = Date.distantPast
''' + method + '''
}
DispatchQueue.main.async {
    let model = Model()
    model.setPresentationActive(false)
    precondition(model.timer.resumes == 0)
    model.setPresentationActive(true)
    precondition(model.timerDate > Date.distantPast && model.timer.resumes == 1)
    model.setPresentationActive(true)
    precondition(model.timer.resumes == 1)
    model.timer.eventHandler?() // Tick queued immediately before screen lock.
    model.setPresentationActive(false)
    model.setPresentationActive(false)
    model.timerDate = Date.distantPast
    precondition(model.timer.suspends == 1)
    DispatchQueue.main.async {
        precondition(model.timerDate == Date.distantPast, "Queued tick updated hidden presentation")
        model.setPresentationActive(true)
        precondition(model.timerDate > Date.distantPast && model.timer.resumes == 2)
        model.timerDate = Date.distantPast
        model.timer.eventHandler?()
        DispatchQueue.main.async {
            precondition(model.timerDate > Date.distantPast, "Visible clock failed to resume")
            model.setPresentationActive(false)
            print("PASS: initial inactivity, idempotent transitions, queued tick after hiding, immediate resume refresh, subsequent visible tick")
            exit(0)
        }
    }
}
dispatchMain()
'''
with tempfile.TemporaryDirectory(prefix='trio-home-clock-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(code)
    subprocess.run(['swift', '-module-cache-path', '/tmp/trio-swift-cache', str(path)], check=True, timeout=60)
