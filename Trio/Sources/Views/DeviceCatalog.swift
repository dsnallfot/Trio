import DanaKit
import MedtrumKit
import OmnipodKit
import UIKit

/// Presentation metadata only. Existing pump setup and CGM plugin identifiers remain authoritative.
enum DeviceManufacturer: String, Hashable {
    case abbott
    case dexcom
    case insulet
    case medtronic
    case medtrum
    case sooil
    case otherSources
    case simulator

    var displayName: String {
        switch self {
        case .abbott: return "Abbott"
        case .dexcom: return "Dexcom"
        case .insulet: return "Insulet"
        case .medtronic: return "Medtronic"
        case .medtrum: return "Medtrum"
        case .sooil: return "SOOIL"
        case .otherSources: return "Övriga källor"
        case .simulator: return "Simulatorer"
        }
    }

    var sortRank: Int {
        switch self {
        case .otherSources: return 1
        case .simulator: return 2
        default: return 0
        }
    }
}

enum DeviceIcon {
    case kit(Bundle, String)
    case uiBundle(String, String)
    case trio(String)
    case none

    var image: UIImage? {
        switch self {
        case let .kit(bundle, asset): return UIImage(named: asset, in: bundle, compatibleWith: nil)
        case let .uiBundle(identifier, asset):
            guard let bundle = Bundle(identifier: identifier) else { return nil }
            return UIImage(named: asset, in: bundle, compatibleWith: nil)
        case let .trio(asset): return UIImage(named: asset)
        case .none: return nil
        }
    }
}

struct DeviceCatalogEntry<Selection>: Identifiable {
    let id: String
    let selection: Selection
    let manufacturer: DeviceManufacturer
    let name: String
    var supportedModels: [String] = []
    var icon: DeviceIcon = .none
    var fallbackSymbolName = "sensor.tag.radiowaves.forward"

    var supportedModelsLine: String? { supportedModels.isEmpty ? nil : supportedModels.joined(separator: ", ") }
    var iconImage: UIImage? { icon.image }
    var hintLine: String { supportedModelsLine.map { "\(name) (\($0))" } ?? name }
}

enum DeviceCatalog {
    static let pumps: [DeviceCatalogEntry<PumpConfig.PumpType>] = [
        .init(
            id: "Omni",
            selection: .omni,
            manufacturer: .insulet,
            name: "Omnipod",
            supportedModels: ["Classic", "DASH", "5"],
            icon: .kit(Bundle(for: OmniPumpManager.self), "Pod"),
            fallbackSymbolName: "ivfluid.bag"
        ),
        .init(
            id: "Minimed500",
            selection: .minimed,
            manufacturer: .medtronic,
            name: "MiniMed",
            supportedModels: ["x15", "x22", "x23", "x54"],
            icon: .uiBundle("org.loopkit.MinimedKitUI", "5xx Small Outline"),
            fallbackSymbolName: "ivfluid.bag"
        ),
        .init(
            id: "Medtrum",
            selection: .medtrum,
            manufacturer: .medtrum,
            name: "Medtrum Nano",
            supportedModels: ["200 E", "300 E"],
            icon: .kit(Bundle(for: MedtrumPumpManager.self), "nano200"),
            fallbackSymbolName: "ivfluid.bag"
        ),
        .init(
            id: "Dana",
            selection: .dana,
            manufacturer: .sooil,
            name: "Dana",
            supportedModels: ["DanaRS", "Dana-i"],
            icon: .kit(Bundle(for: DanaKitPumpManager.self), "danars"),
            fallbackSymbolName: "ivfluid.bag"
        ),
        .init(
            id: "MockPumpManager",
            selection: .simulator,
            manufacturer: .simulator,
            name: "Pumpsimulator",
            icon: .uiBundle("com.loopkit.MockKitUI", "Pump Simulator"),
            fallbackSymbolName: "ivfluid.bag"
        )
    ]

    /// Preserve the complete runtime plugin inventory, including unknown future plugins and the None option.
    static func cgms(_ models: [cgmName]) -> [DeviceCatalogEntry<cgmName>] {
        models.map { model in
            var entry = DeviceCatalogEntry(
                id: model.id,
                selection: model,
                manufacturer: manufacturer(for: model),
                name: model.type == .none ? "Ingen" : model.displayName
            )
            switch model.id {
            case "DexG6Transmitter": entry.icon = .uiBundle("com.loopkit.CGMBLEKitUI", "g6")
            case "G7CGMManager": entry.icon = .uiBundle("org.loopkit.G7SensorKitUI", "g7")
            default: break
            }
            switch model.type {
            case .nightscout: entry.icon = .trio("owl")
            case .simulator: entry.icon = .uiBundle("com.loopkit.MockKitUI", "CGM Simulator")
            case .none: entry.fallbackSymbolName = "nosign"
            default: break
            }
            return entry
        }
    }

    private static func manufacturer(for model: cgmName) -> DeviceManufacturer {
        switch model.type {
        case .simulator: return .simulator
        case .enlite: return .medtronic
        case .nightscout,
             .none,
             .xdrip: return .otherSources
        case .plugin:
            switch model.id {
            case "DexG5Transmitter",
                 "DexG6Transmitter",
                 "G7CGMManager": return .dexcom
            case "LibreTransmitterManagerV3": return .abbott
            case "LibreDemoCGMManager": return .simulator
            default: return .otherSources
            }
        }
    }

    static func sections<Selection>(for entries: [DeviceCatalogEntry<Selection>])
        -> [(manufacturer: DeviceManufacturer, entries: [DeviceCatalogEntry<Selection>])]
    {
        Dictionary(grouping: entries, by: \.manufacturer)
            .map { (manufacturer: $0.key, entries: $0.value) }
            .sorted {
                ($0.manufacturer.sortRank, $0.manufacturer.displayName) < ($1.manufacturer.sortRank, $1.manufacturer.displayName)
            }
    }
}
