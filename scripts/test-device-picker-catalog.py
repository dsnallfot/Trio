#!/usr/bin/env python3
"""Compile the presentation catalog with lightweight image/driver doubles and verify selection preservation."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
catalog = (root / 'Trio/Sources/Views/DeviceCatalog.swift').read_text()
catalog = '\n'.join(line for line in catalog.splitlines() if not line.startswith('import '))
pump_source = (root / 'Trio/Sources/Modules/PumpConfig/PumpConfigDataFlow.swift').read_text()
pump_enum = pump_source.split('    enum PumpType:', 1)[1].split('\n    }', 1)[0]
cgm_source = (root / 'Trio/Sources/Modules/CGM/CGMStateModel.swift').read_text()
cgm_model = 'struct cgmName:' + cgm_source.split('struct cgmName:', 1)[1].split('\n}', 1)[0] + '\n}'
fixture = '''import Foundation
class DanaKitPumpManager: NSObject {}
class MedtrumPumpManager: NSObject {}
class OmniPumpManager: NSObject {}
struct UIImage {
    init?(named: String) {}
    init?(named: String, in bundle: Bundle, compatibleWith: Any?) {}
}
enum CGMType: String { case none, nightscout, xdrip, simulator, enlite, plugin }
enum PumpConfig { enum PumpType:''' + pump_enum + '\n}}\n' + cgm_model
checks = r'''
let models: [cgmName] = [
    .init(id: "none", type: .none, displayName: "None", subtitle: "None"),
    .init(id: "nightscout", type: .nightscout, displayName: "Nightscout", subtitle: ""),
    .init(id: "simulator", type: .simulator, displayName: "Simulator", subtitle: ""),
    .init(id: "enlite", type: .enlite, displayName: "Enlite", subtitle: ""),
    .init(id: "xdrip", type: .xdrip, displayName: "xDrip", subtitle: ""),
    .init(id: "G7CGMManager", type: .plugin, displayName: "Dexcom G7", subtitle: ""),
    .init(id: "DexShareClient", type: .plugin, displayName: "Dexcom Share", subtitle: ""),
    .init(id: "LibreDemoCGMManager", type: .plugin, displayName: "Libre Demo", subtitle: ""),
    .init(id: "FuturePlugin", type: .plugin, displayName: "Future plugin", subtitle: "")
]
let entries = DeviceCatalog.cgms(models)
precondition(entries.map(\.selection) == models, "picker must preserve original CGM values and identifiers")
let sections = DeviceCatalog.sections(for: entries)
precondition(sections.flatMap(\.entries).count == models.count)
precondition(Set(sections.flatMap(\.entries).map(\.id)) == Set(models.map(\.id)))
precondition(sections.last?.manufacturer == .simulator)
precondition(entries.first?.name == "Ingen")
precondition(entries.first { $0.id == "FuturePlugin" }?.manufacturer == .otherSources)
precondition(entries.first { $0.id == "LibreDemoCGMManager" }?.manufacturer == .simulator)
let pumps = DeviceCatalog.pumps
precondition(pumps.count == 5 && Set(pumps.map(\.id)).count == 5)
let expected: [(String, PumpConfig.PumpType)] = [("Omni", .omni), ("Minimed500", .minimed), ("Medtrum", .medtrum), ("Dana", .dana), ("MockPumpManager", .simulator)]
for (id, type) in expected { precondition(pumps.first { $0.id == id }?.selection == type) }
precondition(DeviceCatalog.sections(for: pumps).last?.manufacturer == .simulator)
precondition(DeviceCatalog.sections(for: [DeviceCatalogEntry<cgmName>]()).isEmpty)
print("PASS: five pump routes, every CGM selection preserved, Share/Demo/None/future plugin retained, grouped once, simulator last")
'''
with tempfile.TemporaryDirectory(prefix='picker-catalog-') as tmp:
    source = Path(tmp) / 'main.swift'
    source.write_text(fixture + '\n' + catalog + '\n' + checks)
    subprocess.run(['swiftc', str(source), '-o', tmp + '/test'], check=True)
    subprocess.run([tmp + '/test'], check=True)
