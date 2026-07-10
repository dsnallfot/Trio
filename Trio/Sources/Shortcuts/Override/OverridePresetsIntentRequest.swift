
import CoreData
import Foundation
import UIKit

@available(iOS 16.0, *) final class OverridePresetsIntentRequest: BaseIntentsRequest {
    enum overridePresetsError: Error {
        case noTempOverrideFound
        case noDurationDefined
        case noActiveOverride
    }

    private var currentBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var previousTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isAwaitingNotification: Bool = false

    func fetchAndProcessOverrides() async -> [OverridePreset] {
        // Fetch all Override Presets via OverrideStorage
        let allOverridePresetsIDs = await overrideStorage.fetchForOverridePresets()

        // Since we are fetching on a different background Thread we need to unpack the NSManagedObjectID on the correct Thread first
        return await coredataContext.perform {
            do {
                let overrideObjects = try allOverridePresetsIDs.compactMap { id in
                    try self.coredataContext.existingObject(with: id) as? OverrideStored
                }

                return overrideObjects.map { object in
                    guard let id = object.id,
                          let name = object.name else { return OverridePreset(id: UUID().uuidString, name: "") }
                    return OverridePreset(id: id, name: name)
                }

            } catch {
                debugPrint(
                    "\(#file) \(#function) \(DebuggingIdentifiers.failed) error while fetching/ processing the overrides Array: \(error.localizedDescription)"
                )
                return [OverridePreset(id: UUID().uuidString, name: "")]
            }
        }
    }

    func fetchIDs(_ uuid: [OverridePreset.ID]) async -> [OverridePreset] {
        await coredataContext.perform {
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", uuid)

            do {
                let result = try self.coredataContext.fetch(fetchRequest)

                if result.isEmpty {
                    debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) No OverrideStored found for ids: \(uuid)")
                    return [OverridePreset(id: UUID().uuidString, name: "")]
                }

                return result.map { overrideStored in
                    OverridePreset(id: overrideStored.id ?? UUID().uuidString, name: overrideStored.name ?? "")
                }
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch Override: \(error.localizedDescription)"
                )
                return [OverridePreset(id: UUID().uuidString, name: "")]
            }
        }
    }

    private func fetchOverrideID(_ preset: OverridePreset) async -> NSManagedObjectID? {
        let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", preset.id)
        fetchRequest.fetchLimit = 1

        return await coredataContext.perform {
            do {
                return try self.coredataContext.fetch(fetchRequest).first?.objectID
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch Override: \(error.localizedDescription)"
                )
                return nil
            }
        }
    }

    @MainActor func enactOverride(_ preset: OverridePreset) async -> Bool {
        // Ensure any previous background task is ended before starting a new one
        if previousTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(previousTaskID)
            debugPrint("🛑 Previous background task ended: \(previousTaskID)")
            previousTaskID = .invalid
        }

        // Start a new background task
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Override Upload") {
            guard backgroundTaskID != .invalid else { return }
            Task {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
            backgroundTaskID = .invalid
        }
        previousTaskID = currentBackgroundTaskID
        currentBackgroundTaskID = backgroundTaskID

        // Define a helper function to ensure proper background task cleanup
        func endBackgroundTask() {
            if currentBackgroundTaskID == backgroundTaskID, currentBackgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundTaskID)
                debugPrint("✅ Successfully ended background task: \(currentBackgroundTaskID)")
                currentBackgroundTaskID = .invalid
            }
        }

        defer {
            endBackgroundTask()
        }

        do {
            // **Disable all previous overrides before proceeding**
            await disableAllActiveOverrides(createOverrideRunEntry: true, shouldStartBackgroundTask: false)

            // Get NSManagedObjectID of Preset
            guard let overrideID = await fetchOverrideID(preset),
                  let overrideObject = try viewContext.existingObject(with: overrideID) as? OverrideStored
            else {
                debugPrint("❌ Failed to fetch override object")
                return false
            }

            // Enable Override
            overrideObject.enabled = true
            overrideObject.date = Date()
            overrideObject.isUploadedToNS = false
            overrideObject.enteredBy = "Trio"

            if viewContext.hasChanges {
                try viewContext.save()
                debugPrint("✅ Override successfully applied and saved.")

                // Notify system that override state has changed
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
            } else {
                debugPrint("ℹ️ No changes detected in Core Data, but override is already active.")
                endBackgroundTask()
                return true
            }

            // Prevent multiple concurrent notification waits
            if !isAwaitingNotification {
                isAwaitingNotification = true
                debugPrint("⌛ Waiting for notification...")
                await awaitNotification(.didUpdateOverrideConfiguration)
                debugPrint("✅ Notification received, continuing...")
                isAwaitingNotification = false
            } else {
                debugPrint("⚠️ Skipping duplicate notification wait.")
            }

            endBackgroundTask()

            return true

        } catch {
            debugPrint("❌ Failed to enact Override: \(error.localizedDescription)")
            endBackgroundTask()
            return false
        }
    }

    func cancelOverride() async {
        await disableAllActiveOverrides(createOverrideRunEntry: true, shouldStartBackgroundTask: true)
    }

    @MainActor func disableAllActiveOverrides(
        createOverrideRunEntry: Bool,
        shouldStartBackgroundTask: Bool = true
    ) async {
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

        if shouldStartBackgroundTask {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Override Cancel") {
                guard backgroundTaskID != .invalid else { return }
                Task {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                backgroundTaskID = .invalid
            }
        }

        // Helper function to end background task safely
        func endBackgroundTask() {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                debugPrint("✅ Successfully ended background task: \(backgroundTaskID)")
                backgroundTaskID = .invalid
            }
        }

        defer {
            endBackgroundTask() // Ensures cleanup even if function exits early
        }

        // Get NSManagedObjectIDs of all active overrides
        let ids = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0)

        do {
            // Fetch existing OverrideStored objects
            let results = try ids.compactMap { id in
                try self.viewContext.existingObject(with: id) as? OverrideStored
            }

            // Return early if no results
            guard !results.isEmpty else {
                debugPrint("ℹ️ No active overrides found to disable")
                return
            }

            // Process each active override
            for overrideToCancel in results {
                // Always create a run record if requested and if there's a start date.
                if createOverrideRunEntry, let startDate = overrideToCancel.date {
                    let newOverrideRunStored = OverrideRunStored(context: viewContext)
                    newOverrideRunStored.id = UUID()
                    newOverrideRunStored.name = overrideToCancel.name
                    newOverrideRunStored.enteredBy = overrideToCancel.enteredBy
                    newOverrideRunStored.startDate = startDate

                    let endDate: Date
                    if !overrideToCancel.indefinite, let durationNumber = overrideToCancel.duration {
                        // Duration is in minutes, so multiply by 60 to get seconds.
                        let plannedEndDate = startDate.addingTimeInterval(TimeInterval(truncating: durationNumber) * 60)
                        // If the override has already reached or passed its planned end, use that; otherwise, use the current time.
                        endDate = Date() > plannedEndDate ? plannedEndDate : Date()
                    } else {
                        // For indefinite overrides, always use the current time.
                        endDate = Date()
                    }
                    newOverrideRunStored.endDate = endDate

                    newOverrideRunStored.target = NSDecimalNumber(
                        decimal: overrideStorage.calculateTarget(override: overrideToCancel)
                    )
                    newOverrideRunStored.override = overrideToCancel
                    newOverrideRunStored.isUploadedToNS = false

                    debugPrint("Created override run record for \(overrideToCancel.name ?? "Unnamed") with endDate \(endDate)")
                }

                // Disable the override.
                overrideToCancel.enabled = false
                overrideToCancel.isUploadedToNS = false

                let plannedEndTime = overrideToCancel.date?
                    .addingTimeInterval(TimeInterval(truncating: overrideToCancel.duration ?? 0) * 60)
                debugPrint(
                    "Disabling override: \(overrideToCancel.name ?? "Unnamed") with planned end time: \(plannedEndTime?.description ?? "Unknown")"
                )
            }

            if viewContext.hasChanges {
                try viewContext.save()
                debugPrint("✅ Overrides successfully disabled and saved.")
                // Notify that override state has changed.
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
            }

            debugPrint("⌛ Waiting for notification...")
            await awaitNotification(.didUpdateOverrideConfiguration)
            debugPrint("✅ Notification received, continuing...")

        } catch {
            debugPrint("❌ Failed to disable active Overrides: \(error.localizedDescription)")
            endBackgroundTask() // Ensure task ends even if an error occurs
        }
    }
}
