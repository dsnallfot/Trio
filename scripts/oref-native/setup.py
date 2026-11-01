from pathlib import Path
import shutil, sys, subprocess
r=Path(sys.argv[1]);d=Path(sys.argv[2]);src=d/'Sources/Trio';src.mkdir(parents=True,exist_ok=True)
for p in (r/'Trio/Sources/APS/OpenAPSSwift').rglob('*.swift'):
 (src/p.name).write_text(p.read_text())
models=['Preferences','PumpSettings','BasalProfileEntry','BGTargets','InsulinSensitivities','CarbRatios','TempTarget','TempBasal','Oref2_variables','Determination','Autosens','CarbsEntry','PumpHistoryEvent','BloodGlucose','TrioSettings','GlucoseNotificationsOption','TotalInsulinDisplayType','HbA1cDisplayUnit','GlucoseColorScheme','TimeInRangeChartStyle','ForecastDisplayType','LockScreenView']
for name in models:
 s=(r/f'Trio/Sources/Models/{name}.swift').read_text()
 for imp in ['import LoopKit\n','import HealthKit\n']:s=s.replace(imp,'')
 if name=='CarbsEntry':s=s[:s.index('extension CarbsEntry {\n    func convertSyncCarb')]
 if name=='PumpHistoryEvent':s=s[:s.index('extension EventType {')]
 if name=='GlucoseColorScheme':s=s[:s.index('extension Color')].replace('import SwiftUI\n','').replace('import UIKit\n','')
 if name=='BloodGlucose':s=s[:s.index('extension BloodGlucose: SavitzkyGolaySmoothable')]
 (src/f'{name}.swift').write_text(s)
for name in ['JSON','Formatters','Decimal+Extensions','Rounding','ConvenienceExtensions','String+Extensions']:
 s=(r/f'Trio/Sources/Helpers/{name}.swift').read_text().replace('import HealthKit\n','').replace('import UIKit','import Foundation')
 (src/f'{name}.swift').write_text(s)
(src/'PlatformSupport.swift').write_text('''import Foundation
// Only non-algorithm app services are stubbed for the macOS test host.
struct Override {}
enum LogCategory { case openAPS, service }
func debug(_ category: LogCategory, _ message: String) {}
func warning(_ category: LogCategory, _ message: String, error: Error? = nil) {}
extension TimeInterval { init(hours: Double) { self = hours * 3600 } }

''')
tests=d/'Tests/TrioTests';shutil.copytree(r/'TrioTests/OpenAPSSwiftTests',tests,dirs_exist_ok=True)
(d/'Package.swift').write_text('''// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "TrioOrefNativeTests", platforms: [.macOS(.v14)], products: [.library(name: "Trio", targets: ["Trio"])], targets: [.target(name: "Trio"), .executableTarget(name: "OrefReplay", dependencies: ["Trio"]), .testTarget(name: "TrioTests", dependencies: ["Trio"], resources: [.copy("json"), .copy("TrioCoreDataPersistentContainer.momd")])])
''')

runner=d/"Sources/OrefReplay";runner.mkdir(parents=True,exist_ok=True)
shutil.copyfile(r/"scripts/oref-native/main.swift",runner/"main.swift")

shutil.copyfile(r/'Trio/Sources/APS/CGM/CGMType.swift',src/'CGMType.swift')
# Exercise the real Core Data activation validators on macOS too.
for entity in ['OverrideStored','TempTargetStored','OverrideRunStored','TempTargetRunStored','PumpEventStored','TempBasalStored','BolusStored']:
 for suffix in ['CoreDataClass','CoreDataProperties']:
  name=f'{entity}+{suffix}.swift'
  shutil.copyfile(r/'Model/Classes+Properties'/name,src/name)

# Compile all historical versions too, to test real lightweight SQLite migration.
subprocess.run(["xcrun", "momc", str(r/"Model/TrioCoreDataPersistentContainer.xcdatamodeld"), str(tests/"TrioCoreDataPersistentContainer.momd")], check=True)

# Use the app’s actual DTO encoding and Core Data mapping for the history round-trip test.
dtos=(r/"Model/Helper/PumpEvent+helper.swift").read_text().split("// Declare helper structs", 1)[1]
(src/"HistoryDTO.swift").write_text("import Foundation\n// Declare helper structs"+dtos)
