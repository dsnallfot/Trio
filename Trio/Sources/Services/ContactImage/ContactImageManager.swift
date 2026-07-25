import Combine
import Contacts
import CoreData
import Swinject

protocol ContactImageManagerDelegate: AnyObject {
    func contactImageManagerDidUpdateState(_ state: ContactImageState)
}

protocol ContactImageManager {
    var delegate: ContactImageManagerDelegate? { get set }
    func requestAccess() async -> Bool
    func createContact(name: String) async -> String?
    func deleteContact(withIdentifier identifier: String) async -> Bool
    func updateContact(withIdentifier identifier: String, newName: String) async -> Bool
    @MainActor func updateContactImageState() async
    @MainActor func refreshContactImagesIfStaleStateChanged() async
    @MainActor func setForceStaleBG(_ forceStaleBG: Bool) async
    func setImageForContact(contactId: String) async
    func validateContactExists(withIdentifier identifier: String) async -> Bool
}

private actor ContactImageRefreshCoordinator {
    private var isRefreshing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isRefreshing {
            isRefreshing = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            isRefreshing = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}

final class BaseContactImageManager: NSObject, ContactImageManager, Injectable {
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var contactImageStorage: ContactImageStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var fileStorage: FileStorage!

    @MainActor private var refreshDebounceTask: Task<Void, Never>?

    private let refreshCoordinator = ContactImageRefreshCoordinator()
    private var lastRenderedBGStaleState: Bool?

    private let contactStore = CNContactStore()
    private let contactOrganizationName = "Trio"

    // Make it read-only from outside the class
    private(set) var state = ContactImageState()

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    // Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseContactImageManager.queue", qos: .background)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    private var units: GlucoseUnits = .mgdL

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = settingsManager.settings.units == .mmolL ? 1 : 0
        formatter.minimumFractionDigits = settingsManager.settings.units == .mmolL ? 1 : 0
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "-"
        return formatter
    }

    weak var delegate: ContactImageManagerDelegate?

    private func currentBGStaleState() -> Bool? {
        guard let lastBGDate = state.lastBGDate else { return nil }
        return Date().timeIntervalSince(lastBGDate) > 5.minutes.timeInterval
    }

    private func markCurrentBGStaleStateAsRendered() {
        lastRenderedBGStaleState = currentBGStaleState()
    }

    @MainActor private func scheduleContactImageRefresh() {
        refreshDebounceTask?.cancel()

        refreshDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }

            guard !Task.isCancelled, let self else {
                return
            }

            await self.performSerializedContactImageRefresh(
                updateState: true
            )
        }
    }

    private func performSerializedContactImageRefresh(
        updateState: Bool
    ) async {
        await refreshCoordinator.acquire()

        if updateState {
            await updateContactImageState()
        }

        await updateContactImagesUnlocked()

        await MainActor.run {
            self.markCurrentBGStaleStateAsRendered()
        }

        await refreshCoordinator.release()
    }

    @MainActor func refreshContactImagesIfStaleStateChanged() async {
        if state.lastBGDate == nil {
            await updateContactImageState()
        }

        guard let isStaleBG = currentBGStaleState() else {
            return
        }

        guard lastRenderedBGStaleState != isStaleBG else {
            return
        }

        await performSerializedContactImageRefresh(
            updateState: true
        )
    }

    @MainActor func setForceStaleBG(_ forceStaleBG: Bool) async {
        if state.lastBGDate == nil {
            await updateContactImageState()
        }

        if forceStaleBG {
            guard let lastBGDate = state.lastBGDate else {
                return
            }

            guard Date().timeIntervalSince(lastBGDate) >= 5.minutes.timeInterval else {
                return
            }
        }

        guard state.forceStaleBG != forceStaleBG else {
            return
        }

        state.forceStaleBG = forceStaleBG

        await performSerializedContactImageRefresh(
            updateState: false
        )
    }

    // Original implementation
    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)
        units = settingsManager.settings.units
        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleContactImageRefresh()
                }
            }
            .store(in: &subscriptions)

        registerHandlers()
    }

    // MARK: - Core Data observation

    private func registerHandlers() {
        coreDataPublisher?
            .filterByEntityName("OrefDetermination")
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleContactImageRefresh()
                }
            }
            .store(in: &subscriptions)
    }

    // MARK: - Core Data Fetches

    private func fetchlastDetermination() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: backgroundContext,
            predicate: NSPredicate(format: "deliverAt >= %@", Date.halfHourAgo as NSDate), // fetches enacted and suggested
            key: "deliverAt",
            ascending: false,
            fetchLimit: 1
        )

        return await backgroundContext.perform {
            guard let fetchedResults = results as? [OrefDetermination] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    private func fetchGlucose() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.predicateFor20MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 3 /// We only need 1-3 values, depending on whether the user wants to show delta or not
        )

        return await backgroundContext.perform {
            guard let glucoseResults = results as? [GlucoseStored] else {
                return []
            }

            return glucoseResults.map(\.objectID)
        }
    }

    private func getCurrentGlucoseTarget() async -> Decimal? {
        let now = Date()
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.timeZone = TimeZone.current

        let bgTargets = await fileStorage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
            ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
            ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        let entries: [(start: String, value: Decimal)] = bgTargets.targets.map { ($0.start, $0.low) }

        for (index, entry) in entries.enumerated() {
            guard let entryTime = dateFormatter.date(from: entry.start) else {
                print("Invalid entry start time: \(entry.start)")
                continue
            }

            let entryComponents = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
            let entryStartTime = calendar.date(
                bySettingHour: entryComponents.hour!,
                minute: entryComponents.minute!,
                second: entryComponents.second!,
                of: now
            )!

            let entryEndTime: Date
            if index < entries.count - 1,
               let nextEntryTime = dateFormatter.date(from: entries[index + 1].start)
            {
                let nextEntryComponents = calendar.dateComponents([.hour, .minute, .second], from: nextEntryTime)
                entryEndTime = calendar.date(
                    bySettingHour: nextEntryComponents.hour!,
                    minute: nextEntryComponents.minute!,
                    second: nextEntryComponents.second!,
                    of: now
                )!
            } else {
                entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
            }

            if now >= entryStartTime, now < entryEndTime {
                return entry.value
            }
        }

        return nil
    }

    // MARK: - Configure ContactImageState in order to update ContactImageImage

    /// Updates the `ContactImageState` with the latest data from Core Data.
    /// This function fetches glucose values and determination entries, processes the data,
    /// and updates the `state` object, which represents the current contact trick state.
    /// - Important: This function must be called on the main actor to ensure thread safety. Otherwise, we would need to ensure thread safety by either using an actor or a perform closure
    @MainActor func updateContactImageState() async {
        // Get NSManagedObjectIDs on backgroundContext
        let glucoseValuesIds = await fetchGlucose()
        let determinationIds = await fetchlastDetermination()

        // Get NSManagedObjects on MainActor
        let glucoseObjects: [GlucoseStored] = await CoreDataStack.shared
            .getNSManagedObject(with: glucoseValuesIds, context: viewContext)
        let lastGlucose = glucoseObjects.first
        let determinationObjects: [OrefDetermination] = await CoreDataStack.shared
            .getNSManagedObject(with: determinationIds, context: viewContext)
        let lastDetermination = determinationObjects.first

        if let firstGlucoseValue = glucoseObjects.first {
            let value = settingsManager.settings.units == .mgdL
                ? Decimal(firstGlucoseValue.glucose)
                : Decimal(firstGlucoseValue.glucose).asMmolL

            state.glucose = Formatter.glucoseFormatter(for: units).string(from: value as NSNumber)
            state.trend = firstGlucoseValue.directionEnum?.symbol

            let delta = glucoseObjects.count >= 2
                ? Decimal(firstGlucoseValue.glucose) - Decimal(glucoseObjects.dropFirst().first?.glucose ?? 0)
                : 0
            let deltaConverted = settingsManager.settings.units == .mgdL ? delta : delta.asMmolL
            state.delta = deltaFormatter.string(from: deltaConverted as NSNumber)

            if let latestGlucoseValue = glucoseObjects.first?.glucose {
                let latestGlucoseConverted = settingsManager.settings.units == .mgdL
                    ? Decimal(latestGlucoseValue)
                    : Decimal(latestGlucoseValue).asMmolL

                // Calculate fifteenMinBg: latest glucose + delta * 2 (WIth G7 ive changed this to 10 min)
                let fifteenMinBgDecimal = latestGlucoseConverted + (deltaConverted * Decimal(2))

                let bgFormatter = NumberFormatter()
                bgFormatter.numberStyle = .decimal
                bgFormatter.maximumFractionDigits = settingsManager.settings.units == .mgdL ? 0 : 1
                bgFormatter.minimumFractionDigits = settingsManager.settings.units == .mgdL ? 0 : 1

                state.fifteenMinBg = bgFormatter.string(from: fifteenMinBgDecimal as NSNumber) ?? "N/A"

                // Set emoji for self.state.fifteenLabel based on fifteenMinBgDecimal
                if fifteenMinBgDecimal > 7.8 {
                    state.fifteenLabel = "⚠️" // Emoji for values higher than 7.8
                } else if fifteenMinBgDecimal < 3.9 {
                    state.fifteenLabel = "🆘" // Emoji for values lower than 3.9
                } else {
                    state.fifteenLabel = "✅" // Emoji for values in-between 3.9 and 7.8
                }
            } else {
                state.fifteenMinBg = "N/A"
                state.fifteenLabel = "❓" // Fallback emoji for unavailable data
            }
        }

        state.lastLoopDate = lastDetermination?.timestamp

        state.lastBGDate = lastGlucose?.date

        // Ett nytt färskt BG ska alltid rensa en tidigare tvingad stale-status.
        // Annars kan forceStaleBG ligga kvar efter ett sensoravbrott och göra
        // ett nytt värde överstruket trots att tidsstämpeln är färsk.
        if let lastBGDate = state.lastBGDate,
           Date().timeIntervalSince(lastBGDate) <= 5.minutes.timeInterval
        {
            state.forceStaleBG = false
        }

        let iobValue = lastDetermination?.iob as? Decimal ?? 0.0
        state.iob = iobValue
        state.iobText = (Formatter.decimalFormatterWithOneFractionDigit.string(from: iobValue as NSNumber) ?? "0.0") + "E"

        // we need to do it complex and unelegant, otherwise unwrapping and parsing of cob results in 0
        if let cobValue = lastDetermination?.cob {
            state.cob = Decimal(cobValue)
            state.cobText = (Formatter.integerFormatter.string(from: Int(cobValue) as NSNumber) ?? "0") + "g"

        } else {
            state.cob = 0
            state.cobText = "0g"
        }

        if let eventualBG = settingsManager.settings.units == .mgdL ? lastDetermination?
            .eventualBG : lastDetermination?
            .eventualBG?.decimalValue.asMmolL as NSDecimalNumber?
        {
            let eventualBGAsString = Formatter.decimalFormatterWithOneFractionDigit.string(from: eventualBG)
            state.eventualBG = eventualBGAsString.map { "⇢ " + $0 }
        }

        // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
        let hardCodedLow = Decimal(55)
        let hardCodedHigh = Decimal(220)
        let isDynamicColorScheme = settingsManager.settings.glucoseColorScheme == .dynamicColor
        let highGlucoseColorValue = isDynamicColorScheme ? hardCodedHigh : settingsManager.settings.highGlucose
        let lowGlucoseColorValue = isDynamicColorScheme ? hardCodedLow : settingsManager.settings.lowGlucose

        state.highGlucoseColorValue = units == .mgdL ? highGlucoseColorValue : highGlucoseColorValue.asMmolL
        state.lowGlucoseColorValue = units == .mgdL ? lowGlucoseColorValue : lowGlucoseColorValue.asMmolL
        // ✅ Hämta target i mg/dL (som din settings/NS typiskt lagrar) och konvertera vid behov
        let targetMgdl = await getCurrentGlucoseTarget() ?? Decimal(100)
        state.targetGlucose = units == .mgdL ? targetMgdl : targetMgdl.asMmolL

        state.glucoseColorScheme = settingsManager.settings.glucoseColorScheme

        // Daniel: Additional labels
        state.iobLabel = "IOB"
        state.cobLabel = "COB"
        state.loopLabel = "Loop"

        // Notify delegate about state update on main thread
        await MainActor.run {
            delegate?.contactImageManagerDidUpdateState(state)
        }
    }

    // MARK: - Interactions with CNContactStore API

    private enum ContactImageWriteResult {
        case updated
        case unchanged
        case contactNotFound
        case failed
    }

    private func writeImage(
        _ imageData: Data,
        toContactWithIdentifier contactId: String
    ) -> ContactImageWriteResult {
        do {
            let predicate = CNContact.predicateForContacts(
                withIdentifiers: [contactId]
            )

            let contacts = try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: [
                    CNContactIdentifierKey as CNKeyDescriptor,
                    CNContactImageDataKey as CNKeyDescriptor
                ]
            )

            guard let contact = contacts.first else {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) Contact with ID \(contactId) not found."
                )
                return .contactNotFound
            }

            if contact.imageData == imageData {
                debugPrint(
                    "Skipped unchanged contact image for \(contactId)"
                )
                return .unchanged
            }

            let mutableContact = contact.mutableCopy() as! CNMutableContact
            mutableContact.imageData = imageData

            let saveRequest = CNSaveRequest()
            saveRequest.update(mutableContact)

            try contactStore.execute(saveRequest)

            debugPrint(
                "\(DebuggingIdentifiers.succeeded) Updated contact image for \(contactId)"
            )

            return .updated
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) Failed to update contact image for \(contactId): \(error)"
            )

            return .failed
        }
    }

    private func findExistingTrioContact(
        named name: String
    ) throws -> CNContact? {
        let predicate = CNContact.predicateForContacts(
            matchingName: name
        )

        let contacts = try contactStore.unifiedContacts(
            matching: predicate,
            keysToFetch: [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor
            ]
        )

        return contacts.first {
            let hasExactName = $0.givenName.compare(
                name,
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ]
            ) == .orderedSame

            let belongsToTrio =
                $0.organizationName == contactOrganizationName

            return hasExactName && belongsToTrio
        }
    }

    private func findLegacyContact(
        named name: String
    ) throws -> CNContact? {
        let predicate = CNContact.predicateForContacts(
            matchingName: name
        )

        let contacts = try contactStore.unifiedContacts(
            matching: predicate,
            keysToFetch: [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor
            ]
        )

        return contacts.first {
            let hasExactName = $0.givenName.compare(
                name,
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ]
            ) == .orderedSame

            let hasNoOrganization = $0.organizationName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty

            return hasExactName && hasNoOrganization
        }
    }

    private func adoptLegacyContact(
        _ contact: CNContact
    ) throws -> String {
        let mutableContact = contact.mutableCopy() as! CNMutableContact
        mutableContact.organizationName = contactOrganizationName

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutableContact)

        try contactStore.execute(saveRequest)

        debugPrint(
            "\(DebuggingIdentifiers.succeeded) Adopted legacy Trio contact \(contact.identifier)"
        )

        return contact.identifier
    }

    /// Checks if the app has access to the user's contacts.
    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func setImageForContact(contactId: String) async {
        guard let contactEntry = await contactImageStorage
            .fetchContactImageEntries()
            .first(where: { $0.contactId == contactId })
        else {
            debugPrint(
                "\(DebuggingIdentifiers.failed) No matching ContactImageEntry found for contact ID: \(contactId)"
            )
            return
        }

        await refreshCoordinator.acquire()

        let newImage = await ContactPicture.getImage(
            contact: contactEntry,
            state: state
        )

        guard let imageData = newImage.pngData() else {
            debugPrint(
                "\(DebuggingIdentifiers.failed) Failed to encode image for contact ID: \(contactId)"
            )

            await refreshCoordinator.release()
            return
        }

        _ = writeImage(
            imageData,
            toContactWithIdentifier: contactId
        )

        await refreshCoordinator.release()
    }

    func updateContactImages() async {
        await refreshCoordinator.acquire()
        await updateContactImagesUnlocked()
        await refreshCoordinator.release()
    }

    private func updateContactImagesUnlocked() async {
        let contactEntries = await contactImageStorage
            .fetchContactImageEntries()

        for contactEntry in contactEntries {
            guard let contactId = contactEntry.contactId else {
                continue
            }

            let newImage = await ContactPicture.getImage(
                contact: contactEntry,
                state: state
            )

            guard let imageData = newImage.pngData() else {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) Failed to encode image for contact ID: \(contactId)"
                )
                continue
            }

            _ = writeImage(
                imageData,
                toContactWithIdentifier: contactId
            )
        }
    }

    func createContact(name: String) async -> String? {
        do {
            if let existingContact = try findExistingTrioContact(
                named: name
            ) {
                debugPrint(
                    "Found existing Trio contact with name: \(name)"
                )
                return existingContact.identifier
            }

            if let legacyContact = try findLegacyContact(
                named: name
            ) {
                return try adoptLegacyContact(
                    legacyContact
                )
            }

            let contact = CNMutableContact()
            contact.givenName = name
            contact.organizationName = contactOrganizationName

            let saveRequest = CNSaveRequest()
            saveRequest.add(
                contact,
                toContainerWithIdentifier: nil
            )

            try contactStore.execute(saveRequest)

            if !contact.identifier.isEmpty {
                return contact.identifier
            }

            guard let createdContact = try findExistingTrioContact(
                named: name
            ) else {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) Contact creation failed: No Trio contact found after save."
                )
                return nil
            }

            return createdContact.identifier
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) Error creating or finding Trio contact: \(error)"
            )
            return nil
        }
    }

    func validateContactExists(
        withIdentifier identifier: String
    ) async -> Bool {
        let predicate = CNContact.predicateForContacts(
            withIdentifiers: [identifier]
        )

        let keys = [
            CNContactIdentifierKey as CNKeyDescriptor
        ]

        do {
            let contacts = try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: keys
            )

            return !contacts.isEmpty
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) Error validating contact: \(error)"
            )
            return false
        }
    }

    /// Deletes a contact from the Apple contact list using its `identifier`.
    /// - Parameter identifier: The unique identifier of the contact.
    /// - Returns: `true` if the contact was successfully deleted, `false` otherwise.
    func deleteContact(withIdentifier identifier: String) async -> Bool {
        do {
            // Attempt to find the contact using its identifier.
            let predicate = CNContact.predicateForContacts(withIdentifiers: [identifier])
            let contacts = try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
            )

            guard let contact = contacts.first else {
                debugPrint("\(DebuggingIdentifiers.failed) Contact with ID \(identifier) not found.")
                return false
            }

            // Contact found -> Delete it.
            let mutableContact = contact.mutableCopy() as! CNMutableContact
            let deleteRequest = CNSaveRequest()
            deleteRequest.delete(mutableContact)

            try contactStore.execute(deleteRequest)
            debugPrint("\(DebuggingIdentifiers.succeeded) Contact successfully deleted: \(identifier)")
            return true
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) Error deleting contact: \(error)")
            return false
        }
    }

    /// Updates an existing contact in the Apple contact list.
    /// - Parameters:
    ///   - identifier: The unique identifier of the contact.
    ///   - newName: The new name to assign to the contact.
    /// - Returns: `true` if the contact was successfully updated, `false` otherwise.
    func updateContact(withIdentifier identifier: String, newName: String) async -> Bool {
        do {
            // Search for the contact using its `identifier`.
            let predicate = CNContact.predicateForContacts(withIdentifiers: [identifier])
            let contacts = try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: [
                    CNContactIdentifierKey as CNKeyDescriptor,
                    CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor,
                    CNContactOrganizationNameKey as CNKeyDescriptor
                ]
            )

            guard let contact = contacts.first else {
                debugPrint("\(DebuggingIdentifiers.failed) Contact with ID \(identifier) not found.")
                return false
            }

            // Update the contact.
            let mutableContact = contact.mutableCopy() as! CNMutableContact
            mutableContact.givenName = newName
            mutableContact.organizationName = contactOrganizationName

            let updateRequest = CNSaveRequest()
            updateRequest.update(mutableContact)

            try contactStore.execute(updateRequest)
            debugPrint("\(DebuggingIdentifiers.succeeded) Contact successfully updated: \(identifier)")
            return true
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) Error updating contact: \(error)")
            return false
        }
    }
}
