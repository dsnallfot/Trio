import CoreData
import Foundation
import HealthKit
import UIKit

extension TrioRemoteControl {
    @discardableResult  func handleMealCommand(_ pushMessage: PushMessage) async -> Bool {
        let diagnosticID = RuntimeDiagnostics.shared.begin("remoteMeal", force: true)
        defer { RuntimeDiagnostics.shared.end("remoteMeal", id: diagnosticID, force: true) }
        // If bolusAmount is not nil but all others are nil, exit early without logging an error
        if pushMessage.bolusAmount != nil,
           pushMessage.carbs == nil,
           pushMessage.fat == nil,
           pushMessage.protein == nil
        {
            return false
        }
        // --- DEDUPE START ---
        let commandKey = remoteCommandDedupKey(for: pushMessage, scope: .meal)

        guard beginRemoteCommandIfNotDuplicate(commandKey) else {
            debug(.remoteControl, "Remote måltid ignorerades som dublett. \(pushMessage.humanReadableDescription())")
            return false
        }

        var shouldKeepMealDedupKey = false

        defer {
            if shouldKeepMealDedupKey {
                finishRemoteCommandDedup(commandKey)
            } else {
                cancelRemoteCommandDedup(commandKey)
            }
        }
        // --- DEDUPE END ---

        let carbsDecimal = pushMessage.carbs != nil ? Decimal(pushMessage.carbs!) : nil
        let fatDecimal = pushMessage.fat != nil ? Decimal(pushMessage.fat!) : nil
        let proteinDecimal = pushMessage.protein != nil ? Decimal(pushMessage.protein!) : nil
        let notes: String
        if let pushNotes = pushMessage.notes, !pushNotes.isEmpty {
            notes = pushNotes + " Inlagt av: Trio (" + pushMessage.user + ")"
        } else {
            notes = " Inlagt av: Trio (📲)"
        }

        guard await validateMealCommand(pushMessage) else { return false }

        let actualDate: Date?
        if let scheduledTime = pushMessage.scheduledTime {
            actualDate = Date(timeIntervalSince1970: scheduledTime)
        } else {
            actualDate = nil
        }

        let mealEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: actualDate,
            carbs: carbsDecimal ?? 0,
            fat: fatDecimal,
            protein: proteinDecimal,
            note: notes,
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: fatDecimal ?? 0 > 0 || proteinDecimal ?? 0 > 0 ? UUID().uuidString : nil
        )

        await carbsStorage.storeCarbs([mealEntry], areFetchedFromRemote: false)

        shouldKeepMealDedupKey = true

        // 1) Upload newly registered carbs directly to Nightscout.
        // 2) Trigger a basal sync so calculations (COB/IOB/etc) update immediately.
        // 3) Upload device status after sync so Nightscout gets fresh deviceStatus.
        do {
            let resolver = TrioApp.resolver

            let nightscoutManager: NightscoutManager? = resolver.resolve(NightscoutManager.self)
            let apsManager: APSManager? = resolver.resolve(APSManager.self)

            if let nightscoutManager {
                debugPrint("Uploading carbs to Nightscout after remote meal command...")
                await nightscoutManager.uploadCarbs()
                debugPrint("Carbs upload to Nightscout finished.")
            } else {
                debugPrint("NightscoutManager not available; skipping carbs upload.")
            }

            if let apsManager {
                debugPrint("Triggering basal sync after carbs upload...")
                await apsManager.determineBasalSync()
                debugPrint("Basal sync triggered after carbs upload.")

                if let nightscoutManager {
                    debugPrint("Uploading deviceStatus to Nightscout after basal sync...")
                    await nightscoutManager.uploadDeviceStatus()
                    debugPrint("deviceStatus upload to Nightscout finished.")
                } else {
                    debugPrint("NightscoutManager not available; skipping deviceStatus upload.")
                }
            } else {
                debugPrint("APSManager not available; skipping basal sync and deviceStatus upload.")
            }
        }

        debug(
            .remoteControl,
            "Remote måltid behandlades framgångsrikt. \(pushMessage.humanReadableDescription())"
        )

        guard settings.settings.notificationsRemote else { return true }

        // Construct the notification body
        let cleanedNotes = notes
            .components(separatedBy: " Inlagt av")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var notificationBody = !cleanedNotes.isEmpty ? "\(cleanedNotes)\n" : ""

        // Create a number formatter for consistent decimal formatting
        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.numberStyle = .decimal

        if let carbs = carbsDecimal, carbs > 0 {
            notificationBody += "Kolhydrater: \(carbs) g\n"
        }
        if let fat = fatDecimal, fat > 0 {
            notificationBody += "Fett: \(fat) g\n"
        }
        if let protein = proteinDecimal, protein > 0 {
            notificationBody += "Protein: \(protein) g\n"
        }
        if let bolusAmount = pushMessage.bolusAmount, bolusAmount > 0 {
            let formattedBolusAmount = numberFormatter.string(from: bolusAmount as NSNumber) ?? "\(bolusAmount)"
            notificationBody += "Bolus: \(formattedBolusAmount) E\n"
        }
        notificationBody += "Inlagt av: \(pushMessage.user)\n"
        // Convert timestamp to HH:mm:ss format
        let date = Date(timeIntervalSince1970: pushMessage.timestamp)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let formattedTime = dateFormatter.string(from: date)
        notificationBody += "Tid: \(formattedTime)\n"
        // Trim trailing newline, if present
        notificationBody = notificationBody.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        // Send success notification
        notificationManager.notifyTrioRemoteControl(
            title: pushMessage.commandType == .editMeal ? "Remote Redigera Måltid" : "Remote Måltid",
            body: notificationBody
        )
        return true
    }

    private func validateMealCommand(_ pushMessage: PushMessage) async -> Bool {
        guard pushMessage.carbs != nil || pushMessage.fat != nil || pushMessage.protein != nil else {
            await logError("Kommandot avvisades: måltidsdata är ofullständiga eller ogiltiga.", pushMessage: pushMessage)
            return false
        }

        guard [pushMessage.carbs, pushMessage.fat, pushMessage.protein].allSatisfy({ ($0 ?? 0) >= 0 }),
              pushMessage.scheduledTime.map({ $0.isFinite && $0 >= 0 && $0 < 253_402_300_800 }) ?? true
        else {
            await logError("Kommandot avvisades: ogiltiga måltidsvärden eller måltidstid.", pushMessage: pushMessage)
            return false
        }
        let carbsDecimal = pushMessage.carbs.map { Decimal($0) }
        let fatDecimal = pushMessage.fat.map { Decimal($0) }
        let proteinDecimal = pushMessage.protein.map { Decimal($0) }
        let settingsSelf = await TrioApp.resolver.resolve(SettingsManager.self)?.settings
        let maxCarbs = settingsSelf?.maxCarbs ?? Decimal(0)
        let maxFat = settingsSelf?.maxFat ?? Decimal(0)
        let maxProtein = settingsSelf?.maxProtein ?? Decimal(0)

        if let carbs = carbsDecimal, carbs > maxCarbs {
            await logError(
                "Kommandot avvisades: mängden kolhydrater (\(carbs)g) överskrider det maximalt tillåtna (\(maxCarbs)g).",
                pushMessage: pushMessage
            )
            return false
        }

        if let fat = fatDecimal, fat > maxFat {
            await logError(
                "Kommandot avvisades: mängden fett (\(fat)g) överskrider det maximalt tillåtna (\(maxFat)g).",
                pushMessage: pushMessage
            )
            return false
        }

        if let protein = proteinDecimal, protein > maxProtein {
            await logError(
                "Kommandot avvisades: mängden protein (\(protein)g) överskrider det maximalt tillåtna (\(maxProtein)g).",
                pushMessage: pushMessage
            )
            return false
        }

        let pushMessageDate = Date(timeIntervalSince1970: pushMessage.timestamp)
        let recentCarbEntries = carbsStorage.recent()
        let carbsAfterPushMessage = recentCarbEntries.filter { $0.createdAt > pushMessageDate }

        if pushMessage.commandType != .editMeal, !carbsAfterPushMessage.isEmpty {
            await logError(
                "Kommandot avvisades: nyare måltidsregistreringar har loggats sedan kommandot skickades.",
                pushMessage: pushMessage
            )
            return false
        }

        return true
    }

    func handleEditMealCommand(_ pushMessage: PushMessage) async {
        // timestamp is the send time; originalTime identifies the existing meal.
        guard let originalTime = pushMessage.originalTime,
              originalTime.isFinite, originalTime >= 0, originalTime < 253_402_300_800
        else {
            await logError("Kommandot avvisades: original_time krävs för måltidsredigering.", pushMessage: pushMessage)
            return
        }
        guard pushMessage.bolusAmount == nil || pushMessage.bolusAmount == 0 else {
            await logError("Kommandot avvisades: måltidsredigering får inte innehålla bolus.", pushMessage: pushMessage)
            return
        }

        guard await validateMealCommand(pushMessage) else { return }
        var replacement = pushMessage
        replacement.scheduledTime = pushMessage.scheduledTime ?? originalTime
        // This is a complete replacement. Omitted nutrients mean zero, not “keep old value”.
        replacement.carbs = pushMessage.carbs ?? 0
        replacement.fat = pushMessage.fat ?? 0
        replacement.protein = pushMessage.protein ?? 0
        replacement.bolusAmount = nil

        // Reserve the entire edit before deletion, including duplicate pushes in flight.
        let key = remoteCommandDedupKey(for: replacement, scope: .editMeal)
        guard beginRemoteCommandIfNotDuplicate(key) else { return }
        var completed = false
        defer {
            if completed {
                finishRemoteCommandDedup(key)
            } else {
                cancelRemoteCommandDedup(key)
            }
        }

        guard await handleDeleteMealCommand(replacement) else { return }
        completed = await handleMealCommand(replacement)
    }

    @discardableResult  func handleDeleteMealCommand(_ pushMessage: PushMessage) async -> Bool {
        let resolver = TrioApp.resolver
        let provider: DataTable.Provider = resolver.resolve(DataTable.Provider.self) ?? DataTable.Provider(resolver: resolver)

        let isEdit = pushMessage.commandType == .editMeal
        guard !isEdit || pushMessage.originalTime != nil else { return false }
        let deletionTimestamp = isEdit ? pushMessage.originalTime! : (pushMessage.scheduledTime ?? pushMessage.timestamp)
        guard deletionTimestamp.isFinite, deletionTimestamp >= 0, deletionTimestamp < 253_402_300_800 else {
            await logError(
                "Kommandot avvisades: ogiltig tidsstämpel för måltidsradering.",
                pushMessage: pushMessage
            )
            return false
        }

        let startDate = Date(timeIntervalSince1970: deletionTimestamp.rounded(.down))

        // Edits require one parent meal in the specified second. Keep legacy delete matching unchanged.
        let endDate = startDate.addingTimeInterval(isEdit ? 1 : 60)

        let backgroundContext = CoreDataStack.shared.newTaskContext()
        let matchingIDs: [NSManagedObjectID]

        do {
            matchingIDs = try await backgroundContext.perform {
                let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
                request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startDate as NSDate, endDate as NSDate)
                if isEdit {
                    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                        request.predicate!, NSPredicate(format: "isFPU == NO")
                    ])
                }
                request.fetchLimit = isEdit ? 2 : 1
                return try backgroundContext.fetch(request).map(\.objectID)
            }
        } catch {
            await logError(
                "Kommandot avvisades: kunde inte söka efter måltid att radera. \(error.localizedDescription)",
                pushMessage: pushMessage
            )
            return false
        }

        guard !isEdit || matchingIDs.count <= 1 else {
            await logError("Kommandot avvisades: flera måltider matchar original_time.", pushMessage: pushMessage)
            return false
        }

        guard let treatmentObjectID = matchingIDs.first else {
            await logError(
                "Kommandot avvisades: ingen matchande måltid hittades för den angivna tiden.",
                pushMessage: pushMessage
            )
            return false
        }

        await deleteMealFromServices(treatmentObjectID, provider: provider)
        guard await carbsStorage.deleteCarbsEntryStored(treatmentObjectID) else {
            await logError("Kommandot avvisades: måltiden kunde inte raderas lokalt.", pushMessage: pushMessage)
            return false
        }

        // An edit recalculates and notifies after the replacement has been stored.
        if isEdit { return true }

        if let apsManager: APSManager = resolver.resolve(APSManager.self) {
            await apsManager.determineBasalSync()
        }

        debug(
            .remoteControl,
            "Remote måltidsradering behandlades framgångsrikt. \(pushMessage.humanReadableDescription())"
        )

        guard settings.settings.notificationsRemote else { return true }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let formattedTime = dateFormatter.string(from: startDate)

        notificationManager.notifyTrioRemoteControl(
            title: "Remote Radera Måltid",
            body: "Tid: \(formattedTime)\nInlagt av: \(pushMessage.user)"
        )
        return true
    }

    private func deleteMealFromServices(_ treatmentObjectID: NSManagedObjectID, provider: DataTable.Provider) async {
        debugPrint("deleteFromServices started for objectID: \(treatmentObjectID)")

        // Request background time on the main actor.
        let bgTaskID: UIBackgroundTaskIdentifier = await MainActor.run {
            var taskID: UIBackgroundTaskIdentifier = .invalid
            taskID = UIApplication.shared.beginBackgroundTask(withName: "DeleteCarbEntry") {
                // This closure is called if the background time expires.
                Task { @MainActor in
                    UIApplication.shared.endBackgroundTask(taskID)
                }
            }
            return taskID
        }

        // Ensure the background task is ended when we're done.
        defer {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(bgTaskID)
                debugPrint("Background task ended for deleteFromServices")
            }
        }

        let taskContext = CoreDataStack.shared.newTaskContext()
        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "deleteCarbsFromServices"

        await taskContext.perform {
            do {
                guard let carbEntry = try taskContext.existingObject(with: treatmentObjectID) as? CarbEntryStored else {
                    debugPrint("Carb entry for deletion not found in deleteFromServices.")
                    return
                }
                debugPrint("Deleting remote services for carbEntry: \(carbEntry)")

                // If the entry has an FPU ID, delete FPU-related remote data.
                if let fpuID = carbEntry.fpuID {
                    debugPrint("Deleting FPU related entries for fpuID: \(fpuID.uuidString)")
                    provider.deleteCarbsFromNightscout(withID: fpuID.uuidString)

                    let healthObjectsToDelete: [HKSampleType?] = [
                        AppleHealthConfig.healthFatObject,
                        AppleHealthConfig.healthProteinObject
                    ]
                    for sampleType in healthObjectsToDelete {
                        if let validSampleType = sampleType {
                            debugPrint(
                                "Deleting meal data from Health for fpuID: \(fpuID.uuidString) and sampleType: \(validSampleType)"
                            )
                            provider.deleteMealDataFromHealth(byID: fpuID.uuidString, sampleType: validSampleType)
                        }
                    }
                }

                // Delete carb entries if they exist.
                if let id = carbEntry.id, let entryDate = carbEntry.date {
                    debugPrint("Deleting carb entry remote services for id: \(id.uuidString)")
                    provider.deleteCarbsFromNightscout(withID: id.uuidString)

                    if let sampleType = AppleHealthConfig.healthCarbObject {
                        debugPrint("Deleting carb meal data from Health for id: \(id.uuidString)")
                        provider.deleteMealDataFromHealth(byID: id.uuidString, sampleType: sampleType)
                    }

                    debugPrint("Deleting carb entry from Tidepool for id: \(id.uuidString)")
                    provider.deleteCarbsFromTidepool(
                        withSyncId: id,
                        carbs: Decimal(carbEntry.carbs),
                        at: entryDate,
                        enteredBy: CarbsEntry.local
                    )
                }
            } catch {
                debugPrint("Error in deleteFromServices: \(error.localizedDescription)")
            }
        }
        debugPrint("deleteFromServices finished for objectID: \(treatmentObjectID)")
    }
}
