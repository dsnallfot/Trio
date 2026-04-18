import CoreData
import Foundation
import HealthKit
import UIKit

extension TrioRemoteControl {
    func handleMealCommand(_ pushMessage: PushMessage) async {
        // If bolusAmount is not nil but all others are nil, exit early without logging an error
        if pushMessage.bolusAmount != nil &&
            pushMessage.carbs == nil &&
            pushMessage.fat == nil &&
            pushMessage.protein == nil
        {
            return
        }
        guard pushMessage.carbs != nil || pushMessage.fat != nil || pushMessage.protein != nil else {
            await logError("Kommandot avvisades: måltidsdata är ofullständiga eller ogiltiga.", pushMessage: pushMessage)
            return
        }

        let carbsDecimal = pushMessage.carbs != nil ? Decimal(pushMessage.carbs!) : nil
        let fatDecimal = pushMessage.fat != nil ? Decimal(pushMessage.fat!) : nil
        let proteinDecimal = pushMessage.protein != nil ? Decimal(pushMessage.protein!) : nil
        let notes: String
        if let pushNotes = pushMessage.notes, !pushNotes.isEmpty {
            notes = pushNotes + " Inlagt av: Trio (" + pushMessage.user + ")"
        } else {
            notes = " Inlagt av: Trio (📲)"
        }

        let settingsSelf = await TrioApp.resolver.resolve(SettingsManager.self)?.settings
        let maxCarbs = settingsSelf?.maxCarbs ?? Decimal(0)
        let maxFat = settingsSelf?.maxFat ?? Decimal(0)
        let maxProtein = settingsSelf?.maxProtein ?? Decimal(0)

        if let carbs = carbsDecimal, carbs > maxCarbs {
            await logError(
                "Kommandot avvisades: mängden kolhydrater (\(carbs)g) överskrider det maximalt tillåtna (\(maxCarbs)g).",
                pushMessage: pushMessage
            )
            return
        }

        if let fat = fatDecimal, fat > maxFat {
            await logError(
                "Kommandot avvisades: mängden fett (\(fat)g) överskrider det maximalt tillåtna (\(maxFat)g).",
                pushMessage: pushMessage
            )
            return
        }

        if let protein = proteinDecimal, protein > maxProtein {
            await logError(
                "Kommandot avvisades: mängden protein (\(protein)g) överskrider det maximalt tillåtna (\(maxProtein)g).",
                pushMessage: pushMessage
            )
            return
        }

        let pushMessageDate = Date(timeIntervalSince1970: pushMessage.timestamp)
        let recentCarbEntries = carbsStorage.recent()
        let carbsAfterPushMessage = recentCarbEntries.filter { $0.createdAt > pushMessageDate }

        if !carbsAfterPushMessage.isEmpty {
            await logError(
                "Kommandot avvisades: nyare måltidsregistreringar har loggats sedan kommandot skickades.",
                pushMessage: pushMessage
            )
            return
        }

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

        guard settings.settings.notificationsRemote else { return }

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
            title: "Remote Måltid",
            body: notificationBody
        )
    }

    func handleDeleteMealCommand(_ pushMessage: PushMessage) async {
        let resolver = TrioApp.resolver
        let provider: DataTable.Provider = resolver.resolve(DataTable.Provider.self) ?? DataTable.Provider(resolver: resolver)

        let deletionTimestamp = pushMessage.scheduledTime ?? pushMessage.timestamp
        let targetDate = Date(timeIntervalSince1970: deletionTimestamp)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: targetDate)
        guard let startDate = calendar.date(from: components) else {
            await logError(
                "Kommandot avvisades: ogiltig tidsstämpel för måltidsradering.",
                pushMessage: pushMessage
            )
            return
        }

        let endDate = startDate.addingTimeInterval(60)

        let backgroundContext = CoreDataStack.shared.newTaskContext()
        var matchingEntries: [CarbEntryStored] = []

        do {
            try await backgroundContext.perform {
                let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
                request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startDate as NSDate, endDate as NSDate)
                request.fetchLimit = 1
                matchingEntries = try backgroundContext.fetch(request)
            }
        } catch {
            await logError(
                "Kommandot avvisades: kunde inte söka efter måltid att radera. \(error.localizedDescription)",
                pushMessage: pushMessage
            )
            return
        }

        guard let fetchedObjectID = matchingEntries.first?.objectID else {
            await logError(
                "Kommandot avvisades: ingen matchande måltid hittades för den angivna tiden.",
                pushMessage: pushMessage
            )
            return
        }

        let mainContext = CoreDataStack.shared.persistentContainer.viewContext
        let entryToDelete: CarbEntryStored

        do {
            entryToDelete = try await mainContext.perform {
                guard let entry = try mainContext.existingObject(with: fetchedObjectID) as? CarbEntryStored else {
                    throw NSError(
                        domain: "TrioRemoteControl",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to re-fetch entry on main context"]
                    )
                }
                return entry
            }
        } catch {
            await logError(
                "Kommandot avvisades: kunde inte läsa måltiden som skulle raderas. \(error.localizedDescription)",
                pushMessage: pushMessage
            )
            return
        }

        let treatmentObjectID = entryToDelete.objectID

        await deleteMealFromServices(treatmentObjectID, provider: provider)
        await carbsStorage.deleteCarbsEntryStored(treatmentObjectID)

        if let apsManager: APSManager = resolver.resolve(APSManager.self) {
            await apsManager.determineBasalSync()
        }

        debug(
            .remoteControl,
            "Remote måltidsradering behandlades framgångsrikt. \(pushMessage.humanReadableDescription())"
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let formattedTime = dateFormatter.string(from: startDate)

        notificationManager.notifyTrioRemoteControl(
            title: "Remote Radera Måltid",
            body: "Tid: \(formattedTime)\nInlagt av: \(pushMessage.user)"
        )
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
