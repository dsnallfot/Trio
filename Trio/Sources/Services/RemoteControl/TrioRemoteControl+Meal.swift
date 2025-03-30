import Foundation

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
            notes = pushNotes + " Inlagt av: Trio(" + pushMessage.user + ")"
        } else {
            notes = "📲"
        }

        let settings = await TrioApp.resolver.resolve(SettingsManager.self)?.settings
        let maxCarbs = settings?.maxCarbs ?? Decimal(0)
        let maxFat = settings?.maxFat ?? Decimal(0)
        let maxProtein = settings?.maxProtein ?? Decimal(0)

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

        debug(
            .remoteControl,
            "Remote måltid behandlades framgångsrikt. \(pushMessage.humanReadableDescription())"
        )
        // Construct the notification body
        var notificationBody = !notes.isEmpty ? "\(notes)\n" : ""

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
}
