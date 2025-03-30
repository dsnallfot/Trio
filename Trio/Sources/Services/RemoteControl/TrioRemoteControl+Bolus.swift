import CoreData
import Foundation

extension TrioRemoteControl {
    internal func handleBolusCommand(_ pushMessage: PushMessage) async {
        guard let bolusAmount = pushMessage.bolusAmount else {
            await logError("Kommandot avvisades: bolusmängd saknas eller är ogiltig.", pushMessage: pushMessage)
            return
        }

        let maxBolus = await TrioApp.resolver.resolve(SettingsManager.self)?.pumpSettings.maxBolus ?? Decimal(0)

        if bolusAmount > maxBolus {
            await logError(
                "Kommandot avvisades: bolusmängden (\(bolusAmount) enheter) överskrider det maximalt tillåtna (\(maxBolus) enheter).",
                pushMessage: pushMessage
            )
            return
        }

        let maxIOB = settings.preferences.maxIOB
        let currentIOB = await fetchCurrentIOB()
        if (currentIOB + bolusAmount) > maxIOB {
            await logError(
                "Kommandot avvisades: bolusmängden (\(bolusAmount) enheter) skulle överskrida max IOB (\(maxIOB) enheter). Nuvarande IOB: \(currentIOB) enheter.",
                pushMessage: pushMessage
            )
            return
        }

        let totalRecentBolusAmount = await fetchTotalRecentBolusAmount(since: Date(timeIntervalSince1970: pushMessage.timestamp))

        if totalRecentBolusAmount >= bolusAmount * 0.2 {
            await logError(
                "Kommandot avvisades: bolusdoser som totalt överstiger 20% av den begärda mängden har levererats sedan kommandot skickades.",
                pushMessage: pushMessage
            )
            return
        }

        debug(.remoteControl, "Utför boluskommando med mängd: \(bolusAmount) enheter.")

        guard let apsManager = await TrioApp.resolver.resolve(APSManager.self) else {
            await logError(
                "Fel: kunde inte bearbeta boluskommando eftersom APS Manager inte är tillgänglig.",
                pushMessage: pushMessage
            )
            return
        }

        await apsManager.enactBolus(amount: Double(truncating: bolusAmount as NSNumber), isSMB: false, callback: nil)

        // Daniel: Add the note from the remote command
        // Instead of updating the event immediately, save the note for later use.
        TrioRemoteControl.pendingRemoteBolusNote = (note: pushMessage.user, timestamp: Date())

        debug(
            .remoteControl,
            "Fjärrkommando behandlades framgångsrikt. \(pushMessage.humanReadableDescription())"
        )
        // Format the bolus amount to 2 decimal places
        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.numberStyle = .decimal
        let formattedBolusAmount = numberFormatter.string(from: bolusAmount as NSNumber) ?? "\(bolusAmount)"
        var notificationBody = "Bolus: \(formattedBolusAmount) E\n"
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
            title: "Remote Bolus",
            body: notificationBody
        )
    }

    // Daneil: Hack to upload the user as enteredBy to NS
    private func updateLatestBolusNote(with noteText: String) {
        let context = CoreDataStack.shared.newTaskContext()
        context.perform {
            let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            // Look for the most recent bolus (e.g. within the last 10 minutes).
            let tenMinutesAgo = Date().addingTimeInterval(-10 * 60)
            fetchRequest.predicate = NSPredicate(
                format: "type == %@ AND timestamp >= %@",
                PumpEventStored.EventType.bolus.rawValue,
                tenMinutesAgo as NSDate
            )
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            fetchRequest.fetchLimit = 1
            do {
                let events = try context.fetch(fetchRequest)
                if let latestBolus = events.first {
                    latestBolus.note = "Trio (\(noteText))"
                    try context.save()
                }
            } catch {
                print("Error updating bolus note: \(error)")
            }
        }
    }

    private func fetchCurrentIOB() async -> Decimal {
        let predicate = NSPredicate.predicateFor30MinAgoForDetermination

        let determinations = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: pumpHistoryFetchContext,
            predicate: predicate,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["iob"]
        )

        guard let fetchedResults = determinations as? [[String: Any]],
              let firstResult = fetchedResults.first,
              let iob = firstResult["iob"] as? Decimal
        else {
            await logError("Misslyckades med att hämta aktuellt IOB.")
            return Decimal(0)
        }

        return iob
    }

    private func fetchTotalRecentBolusAmount(since date: Date) async -> Decimal {
        let predicate = NSPredicate(
            format: "type == %@ AND timestamp > %@",
            PumpEventStored.EventType.bolus.rawValue,
            date as NSDate
        )

        let results: Any = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: pumpHistoryFetchContext,
            predicate: predicate,
            key: "timestamp",
            ascending: true,
            fetchLimit: nil,
            propertiesToFetch: ["bolus.amount"]
        )

        guard let bolusDictionaries = results as? [[String: Any]] else {
            await logError("Misslyckades med att konvertera hämtade bolushändelser. Hämtad enhetstyp: \(type(of: results))")
            return 0
        }

        let totalAmount = bolusDictionaries.compactMap { ($0["bolus.amount"] as? NSNumber)?.decimalValue }.reduce(0, +)

        return totalAmount
    }
}
