import Foundation
import LoopKit
import Swinject
import UIKit

// Daniel: Testar att alltid ladda upp ändrade inställningar till NS (original kod finns utkommenterad nedan om återställning behövs)
protocol SettingsManager: AnyObject {
    var settings: TrioSettings { get set }
    var preferences: Preferences { get set }
    var pumpSettings: PumpSettings { get }
    func updateInsulinCurve(_ insulinType: InsulinType?)
}

protocol SettingsObserver {
    func settingsDidChange(_: TrioSettings)
}

protocol PreferencesObserver {
    func preferencesDidChange(_: Preferences)
}

final class BaseSettingsManager: SettingsManager, Injectable {
    @Injected() var broadcaster: Broadcaster!
    @Injected() var storage: FileStorage!

    // Instead of direct injection, store the resolver.
    private let resolver: Resolver
    // Lazy resolve the NightscoutManager only when first accessed.
    private lazy var nightscout: NightscoutManager = {
        self.resolver.resolve(NightscoutManager.self)!
    }()

    // For debouncing settings
    private var pendingUploadWorkItem: DispatchWorkItem?
    private var debounceOldSettings: TrioSettings?
    private let debounceInterval: TimeInterval = 15 // Adjust as needed

    // For debouncing preferences
    private var pendingUploadWorkItemPreferences: DispatchWorkItem?
    private var debounceOldPreferences: Preferences?

    private func startBackgroundTask(named name: String) -> UIBackgroundTaskIdentifier {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: name) {
            UIApplication.shared.endBackgroundTask(taskID)
        }
        return taskID
    }

    @SyncAccess var settings: TrioSettings {
        didSet {
            if oldValue != settings {
                saveSettings()
                DispatchQueue.main.async {
                    self.broadcaster.notify(SettingsObserver.self, on: .main) {
                        $0.settingsDidChange(self.settings)
                    }
                }

                if pendingUploadWorkItem == nil {
                    debounceOldSettings = oldValue
                }

                pendingUploadWorkItem?.cancel()

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, let originalSettings = self.debounceOldSettings else { return }
                    let changeNote = self.computeDiff(old: originalSettings, new: self.settings)
                    print("Debounced settings change: \(changeNote)")

                    // Begin a background task to ensure the upload completes if app goes to background.
                    let bgTask = self.startBackgroundTask(named: "UploadSettings")

                    Task.detached(priority: .low) {
                        await self.nightscout.uploadProfiles(alsoUploadNote: true, note: changeNote)
                        await UIApplication.shared.endBackgroundTask(bgTask)
                    }

                    self.pendingUploadWorkItem = nil
                    self.debounceOldSettings = nil
                }

                pendingUploadWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
            }
        }
    }

    @SyncAccess var preferences: Preferences {
        didSet {
            if oldValue != preferences {
                savePreferences()
                DispatchQueue.main.async {
                    self.broadcaster.notify(PreferencesObserver.self, on: .main) {
                        $0.preferencesDidChange(self.preferences)
                    }
                }

                // Capture the initial old preferences value if not already debouncing.
                if pendingUploadWorkItemPreferences == nil {
                    debounceOldPreferences = oldValue
                }

                // Cancel any pending work item for preferences.
                pendingUploadWorkItemPreferences?.cancel()

                // Create a new work item for debouncing the upload.
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, let originalPreferences = self.debounceOldPreferences else { return }
                    let changeNote = self.computeDiff(old: originalPreferences, new: self.preferences)
                    print("Debounced preferences change: \(changeNote)")

                    // Begin a background task using the helper
                    let bgTask = self.startBackgroundTask(named: "UploadPreferences")

                    Task.detached(priority: .low) {
                        await self.nightscout.uploadProfiles(alsoUploadNote: true, note: changeNote)
                        await UIApplication.shared.endBackgroundTask(bgTask)
                    }

                    // Reset debouncing state.
                    self.pendingUploadWorkItemPreferences = nil
                    self.debounceOldPreferences = nil
                }

                pendingUploadWorkItemPreferences = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
            }
        }
    }

    private func saveSettings() {
        storage.save(settings, as: OpenAPS.Trio.settings)
    }

    private func savePreferences() {
        storage.save(preferences, as: OpenAPS.Settings.preferences)
    }

    /// Generic diff function using Mirror to compare two values.
    /// Returns a string containing lines like "property: oldValue -> newValue".
    private func computeDiff<T>(old: T, new: T) -> String {
        let oldMirror = Mirror(reflecting: old)
        let newMirror = Mirror(reflecting: new)
        var changes: [String] = []
        for child in oldMirror.children {
            guard let label = child.label else { continue }
            if let newChild = newMirror.children.first(where: { $0.label == label }) {
                let oldValue = "\(child.value)"
                let newValue = "\(newChild.value)"
                if oldValue != newValue {
                    changes.append("\(label): \(oldValue)➔\(newValue)")
                }
            }
        }
        return changes.isEmpty ? "No detailed changes captured" : "Justerad inställning: " + changes.joined(separator: ", ")
    }

    init(resolver: Resolver) {
        self.resolver = resolver
        let storage = resolver.resolve(FileStorage.self)!
        settings = storage.retrieve(OpenAPS.Trio.settings, as: TrioSettings.self)
            ?? TrioSettings(from: OpenAPS.defaults(for: OpenAPS.Trio.settings))
            ?? TrioSettings()

        preferences =
            storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
                ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
                ?? Preferences()

        injectServices(resolver)
    }

    var pumpSettings: PumpSettings {
        storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
            ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
            ?? PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
    }

    func updateInsulinCurve(_ insulinType: InsulinType?) {
        var prefs = preferences

        switch insulinType {
        case .apidra,
             .humalog,
             .novolog:
            prefs.curve = .rapidActing
        case .fiasp,
             .lyumjev:
            prefs.curve = .ultraRapid
        default:
            prefs.curve = .rapidActing
        }

        preferences = prefs
        savePreferences()
    }
}

/*
 import Foundation
 import LoopKit
 import Swinject

 protocol SettingsManager: AnyObject {
     var settings: TrioSettings { get set }
     var preferences: Preferences { get set }
     var pumpSettings: PumpSettings { get }
     func updateInsulinCurve(_ insulinType: InsulinType?)
 }

 protocol SettingsObserver {
     func settingsDidChange(_: TrioSettings)
 }

 protocol PreferencesObserver {
     func preferencesDidChange(_: Preferences)
 }

 final class BaseSettingsManager: SettingsManager, Injectable {
     @Injected() var broadcaster: Broadcaster!
     @Injected() var storage: FileStorage!

     @SyncAccess var settings: TrioSettings {
         didSet {
             if oldValue != settings {
                 saveSettings()
                 DispatchQueue.main.async {
                     self.broadcaster.notify(SettingsObserver.self, on: .main) {
                         $0.settingsDidChange(self.settings)
                     }
                 }
             }
         }
     }

     @SyncAccess var preferences: Preferences {
         didSet {
             if oldValue != preferences {
                 savePreferences()
                 DispatchQueue.main.async {
                     self.broadcaster.notify(PreferencesObserver.self, on: .main) {
                         $0.preferencesDidChange(self.preferences)
                     }
                 }
             }
         }
     }

     private func saveSettings() {
         storage.save(settings, as: OpenAPS.Trio.settings)
     }

     private func savePreferences() {
         storage.save(preferences, as: OpenAPS.Settings.preferences)
     }

     init(resolver: Resolver) {
         let storage = resolver.resolve(FileStorage.self)!
         settings = storage.retrieve(OpenAPS.Trio.settings, as: TrioSettings.self)
             ?? TrioSettings(from: OpenAPS.defaults(for: OpenAPS.Trio.settings))
             ?? TrioSettings()

         preferences =
             storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
                 ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
                 ?? Preferences()

         injectServices(resolver)
     }

     var pumpSettings: PumpSettings {
         storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
             ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
             ?? PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
     }

     func updateInsulinCurve(_ insulinType: InsulinType?) {
         var prefs = preferences

         switch insulinType {
         case .apidra,
              .humalog,
              .novolog:
             prefs.curve = .rapidActing

         case .fiasp,
              .lyumjev:
             prefs.curve = .ultraRapid
         default:
             prefs.curve = .rapidActing
         }

         preferences = prefs
         savePreferences()
     }
 }
 */
