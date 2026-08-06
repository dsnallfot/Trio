import CoreData
import SwiftUI

struct ContactImageEntry: Hashable, Equatable, Sendable {
    var id = UUID()
    var name: String = ""
    var layout: ContactImageLayout = .default
    var ring: ContactImageLargeRing = .none
    var primary: ContactImageValue = .glucose
    var top: ContactImageValue = .none
    var bottom: ContactImageValue = .none
    var contactId: String? = nil
    var hasHighContrast: Bool = true
    var ringWidth: RingWidth = .regular
    var ringGap: RingGap = .small
    var fontSize: FontSize = .regular
    var secondaryFontSize: FontSize = .small
    var fontWeight: Font.Weight = .medium
    var fontWidth: Font.Width = .standard
    var managedObjectID: NSManagedObjectID?

    static func == (lhs: ContactImageEntry, rhs: ContactImageEntry) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.layout == rhs.layout &&
            lhs.ring == rhs.ring &&
            lhs.primary == rhs.primary &&
            lhs.top == rhs.top &&
            lhs.bottom == rhs.bottom &&
            lhs.contactId == rhs.contactId &&
            lhs.hasHighContrast == rhs.hasHighContrast &&
            lhs.ringWidth == rhs.ringWidth &&
            lhs.ringGap == rhs.ringGap &&
            lhs.fontSize == rhs.fontSize &&
            lhs.secondaryFontSize == rhs.secondaryFontSize &&
            lhs.fontWeight == rhs.fontWeight &&
            lhs.fontWidth == rhs.fontWidth
    }

    // Convert `fontWeight` to a String for Core Data storage
    var fontWeightString: String {
        fontWeight.asString
    }

    // Initialize `fontWeight` from a String
    static func fontWeight(from string: String) -> Font.Weight {
        Font.Weight.fromString(string)
    }

    // Convert `fontWidth` to a String for Core Data storage
    var fontWidthString: String {
        fontWidth.asString
    }

    // Initialize `fontWidth` from a String
    static func fontWidth(from string: String) -> Font.Width {
        Font.Width.fromString(string)
    }

    enum FontSize: Int, Codable, Sendable, CaseIterable {
        case tiny = 200
        case small = 250
        case regular = 300
        case large = 400

        var displayName: String {
            switch self {
            case .tiny: return "Mini"
            case .small: return "Liten"
            case .regular: return "Normal"
            case .large: return "Stor"
            }
        }
    }

    enum RingWidth: Int, Codable, Sendable, CaseIterable {
        case tiny = 3
        case small = 5
        case regular = 7
        case medium = 10
        case large = 15

        var displayName: String {
            switch self {
            case .tiny: return "Mini"
            case .small: return "Liten"
            case .regular: return "Normal"
            case .medium: return "Medium"
            case .large: return "Stor"
            }
        }
    }

    enum RingGap: Int, Codable, Sendable, CaseIterable {
        case tiny = 1
        case small = 2
        case regular = 3
        case medium = 4
        case large = 5

        var displayName: String {
            switch self {
            case .tiny: return "Mini"
            case .small: return "Litet"
            case .regular: return "Normalt"
            case .medium: return "Medium"
            case .large: return "Stort"
            }
        }
    }
}

protocol ContactImageObserver: Sendable {
    // TODO: is this required?
//    func basalProfileDidChange(_ entry: [ContactImageEntry])
}

enum ContactImageValue: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case none
    case glucose
    case eventualBG
    case delta
    case trend
    case fifteenMinBg
    case lastLoopDate
    case lastBGDate
    case cob
    case iob
    case ring
    case fifteenLabel
    case iobLabel
    case cobLabel
    case loopLabel

    var displayName: String {
        switch self {
        case .none:
            return NSLocalizedString("Ingen", comment: "")
        case .glucose:
            return NSLocalizedString("Glukosevärde", comment: "")
        case .eventualBG:
            return NSLocalizedString("Prognos", comment: "")
        case .delta:
            return NSLocalizedString("Glukosdelta", comment: "")
        case .trend:
            return NSLocalizedString("Glukostrend", comment: "")
        case .fifteenMinBg:
            return NSLocalizedString("15 min trend", comment: "")
        case .lastLoopDate:
            return NSLocalizedString("Senaste loop", comment: "")
        case .lastBGDate:
            return NSLocalizedString("Senaste glukos", comment: "")
        case .cob:
            return NSLocalizedString("COB", comment: "")
        case .iob:
            return NSLocalizedString("IOB", comment: "")
        case .ring:
            return NSLocalizedString("Loopstatus", comment: "")
        case .fifteenLabel:
            return NSLocalizedString("15 min rubrik", comment: "")
        case .iobLabel:
            return NSLocalizedString("IOB rubrik", comment: "")
        case .cobLabel:
            return NSLocalizedString("COB rubrik", comment: "")
        case .loopLabel:
            return NSLocalizedString("Loop rubrik", comment: "")
        }
    }
}

enum ContactImageLayout: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case `default`
    case split

    var displayName: String {
        switch self {
        case .default:
            return NSLocalizedString("Standard", comment: "")
        case .split:
            return NSLocalizedString("Delad", comment: "")
        }
    }
}

enum ContactImageLargeRing: String, JSON, CaseIterable, Identifiable, Codable {
    // TODO: revisit rings for iob, cob and combined iob+cob with more user feedback
    var id: String { rawValue }
    case none
    case loop
//    case iob
//    case cob
//    case iobcob

    var displayName: String {
        switch self {
        case .none:
            return NSLocalizedString("Dold", comment: "")
        case .loop:
            return NSLocalizedString("Loopstatus", comment: "")
//        case .iob:
//            return NSLocalizedString("Insulin on Board (IOB)", comment: "")
//        case .cob:
//            return NSLocalizedString("Carbs on Board (COB)", comment: "")
//        case .iobcob:
//            return NSLocalizedString("IOB + COB", comment: "")
        }
    }
}
