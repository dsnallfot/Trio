#!/usr/bin/env python3
"""Exercise production cache/key logic with a counting renderer (no Contacts writes)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
base = root / 'Trio/Sources/Services/ContactImage'
picture = (base / 'ContactPicture.swift').read_text()
manager = (base / 'ContactImageManager.swift').read_text()
state = (base / 'ContactImageState.swift').read_text()

def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

key = section(picture, '    struct RenderKey:', '    static func getImage(')
minutes = section(picture, '    private static func minutesAgoText', '    private static func drawText')
loop = section(picture, '    private static func loopAgeCategory', '    private static func ringColor')
cache = section(manager, '    @MainActor private func pruneRenderedImages', '    func createContact(name: String) async -> String? {').replace('private func', 'func')
code = '''import Foundation
import Darwin
struct BloodGlucose { enum Direction: String, Codable { case flat, singleUp } }
enum GlucoseColorScheme: String, Codable { case staticColor, dynamicColor }
struct ContactImageEntry: Equatable {
    enum Layout { case bobble, other }
    var id = UUID()
    var managedObjectID: String?
    var contactId: String? = "one"
    var layout: Layout = .other
    var bobbleShowMinutesAgo = true
    var style = 0
}
struct UITraitCollection: Equatable { static var current = UITraitCollection() }
extension Int { var minutes: Double { Double(self) * 60 } }
extension Double { var timeInterval: Double { self } }
''' + state + '''
@MainActor struct ContactPicture {
    private enum Config {
        static let lag: TimeInterval = 30
        static let staleBGThreshold: TimeInterval = 300
    }
''' + key + minutes + loop + '''
    static var renders = 0
    static var failEncoding = false
    struct Image {
        @MainActor func pngData() -> Data? { failEncoding ? nil : Data([UInt8(renders)]) }
    }
    static func getImage(contact: ContactImageEntry, state: ContactImageState, now: Date) -> Image {
        renders += 1
        return Image()
    }
}
@MainActor final class Manager {
    var state = ContactImageState()
    var renderedImages: [String: (key: ContactPicture.RenderKey, data: Data)] = [:]
''' + cache + '''
}
Task { @MainActor in
    let t = Date(timeIntervalSince1970: 1_700_000_000)
    let manager = Manager()
    var entry = ContactImageEntry()
    manager.state.glucose = "6.0"
    manager.state.lastBGDate = t
    manager.state.glucoseDate = t
    manager.state.lastLoopDate = t
    @MainActor func data(_ seconds: Double) -> Data? {
        manager.renderedImageData(for: entry, now: t.addingTimeInterval(seconds))
    }
    let first = data(10)
    precondition(first != nil && data(20) == first && ContactPicture.renders == 1,
                 "Duplicate input must not render or encode again")
    entry.id = UUID() // Core Data creates a fresh UI identity on each fetch.
    precondition(data(20) == first && ContactPicture.renders == 1)
    manager.state.glucose = "6.1"
    precondition(data(20) != first, "New glucose must refresh")
    let fresh = data(300)
    precondition(data(300.01) != fresh, "Stale transition must refresh without new data")
    let green = data(330)
    precondition(data(330.01) != green, "Loop ring must become yellow after 5m + lag")
    let yellow = data(630)
    precondition(data(630.01) != yellow, "Loop ring must become red after 10m + lag")
    let previous = data(10)
    manager.state.forceStaleBG = true
    precondition(data(10) != previous, "Forced stale state must refresh")
    manager.state.forceStaleBG = false
    let forced = data(10)
    entry.style = 1
    precondition(data(10) != forced, "Contact settings must refresh")
    entry.layout = .bobble
    let minute1 = data(89)
    precondition(data(90) != minute1, "Rounded bobble age must refresh at 1.5 minutes")
    entry.bobbleShowMinutesAgo = false
    let hiddenAge = data(89)
    precondition(data(90) == hiddenAge, "Hidden bobble age must not cause a render")
    manager.state.delta = "+0.2"
    ContactPicture.failEncoding = true
    precondition(data(90) == nil && manager.renderedImages.isEmpty)
    ContactPicture.failEncoding = false
    precondition(data(90) != nil, "Encoding failure must allow retry")
    entry.contactId = "two"
    precondition(data(90) != nil && manager.renderedImages.count == 2)
    manager.pruneRenderedImages(keeping: ["two"])
    precondition(manager.renderedImages.count == 1 && manager.renderedImages["one"] == nil)
    let renders = ContactPicture.renders
    _ = data(90) // Reuse still returns bytes for the unchanged Contacts write/check path.
    precondition(ContactPicture.renders == renders)
    print("PASS: duplicate rendering, new values/settings, stale and ring thresholds, bobble age, encoding retry, per-contact pruning")
    exit(0)
}
dispatchMain()
'''
with tempfile.TemporaryDirectory(prefix='trio-contact-cache-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(code)
    subprocess.run(['swift', '-module-cache-path', '/tmp/trio-swift-cache', str(path)], check=True, timeout=60)
