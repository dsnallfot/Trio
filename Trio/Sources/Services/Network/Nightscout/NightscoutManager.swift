import Combine
import CoreData
import Foundation
import LoopKitUI
import Swinject
import UIKit

protocol NightscoutManager: GlucoseSource {
    func fetchGlucose(since date: Date) async -> [BloodGlucose]
    func fetchCarbs() async -> [CarbsEntry]
    func fetchTempTargets() async -> [TempTarget]
    func deleteCarbs(withID id: String) async
    func deleteInsulin(withID id: String) async
    func deleteManualGlucose(withID id: String) async
    func deleteGlucose(withID id: String) async
    func uploadDeviceStatus() async
    func uploadErrors(withNotes notes: String) async
    func uploadGlucose() async
    func uploadCarbs() async
    func uploadPumpHistory() async
    func uploadOverrides() async
    func uploadTempTargets() async
    func uploadManualGlucose() async
    func uploadProfiles(alsoUploadNote: Bool, note: String) async
    func uploadNoteTreatment(note: String) async
    func importSettings() async -> ScheduledNightscoutProfile?
    var cgmURL: URL? { get }
}

final class BaseNightscoutManager: NightscoutManager, Injectable {
    @Injected() private var keychain: Keychain!
    @Injected() private var determinationStorage: DeterminationStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var overridesStorage: OverrideStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var reachabilityManager: ReachabilityManager!
    @Injected() var healthkitManager: HealthKitManager!

    private let orefDeterminationSubject = PassthroughSubject<Void, Never>()
    private let uploadOverridesSubject = PassthroughSubject<Void, Never>()
    private let uploadPumpHistorySubject = PassthroughSubject<Void, Never>()
    private let uploadCarbsSubject = PassthroughSubject<Void, Never>()
    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")
    private var ping: TimeInterval?

    private var backgroundContext = CoreDataStack.shared.newTaskContext()

    private var lifetime = Lifetime()

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private var isUploadEnabled: Bool {
        settingsManager.settings.isUploadEnabled
    }

    private var isErrorUploadEnabled: Bool {
        settingsManager.settings.isErrorUploadEnabled
    }

    private var isDownloadEnabled: Bool {
        settingsManager.settings.isDownloadEnabled
    }

    private var isUploadGlucoseEnabled: Bool {
        settingsManager.settings.uploadGlucose
    }

    private var isConnectedToLocalSkynetWiFi: Bool {
        currentWiFiIPv4Address == "192.168.0.246"
    }

    private var currentWiFiIPv4Address: String? {
        var address: String?
        var interfaces: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaces) == 0 else {
            return nil
        }

        defer {
            freeifaddrs(interfaces)
        }

        var pointer = interfaces
        while pointer != nil {
            guard let interface = pointer?.pointee else {
                pointer = pointer?.pointee.ifa_next
                continue
            }

            let interfaceName = String(cString: interface.ifa_name)
            let family = interface.ifa_addr.pointee.sa_family

            if interfaceName == "en0", family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                address = String(cString: hostname)
                break
            }

            pointer = interface.ifa_next
        }

        return address
    }

    private var nightscoutAPI: NightscoutAPI? {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let url = URL(string: urlString),
              let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        else {
            return nil
        }
        return NightscoutAPI(url: url, secret: secret)
    }

    private var lastEnactedDetermination: Determination?
    private var lastSuggestedDetermination: Determination?

    // Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseNightscoutManager.queue", qos: .utility)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        registerSubscribers()
        registerHandlers()
        setupNotification()

        /// Ensure that Nightscout Manager holds the `lastEnactedDetermination`, if one exists, on initialization.
        /// We have to set this here in `init()`, so there's a `lastEnactedDetermination` available after an app restart
        /// for `uploadDeviceStatus()`, as within that fuction `lastEnactedDetermination` is reassigned at the very end of the function.
        /// This way, we ensure the latest enacted determination is always part of `devicestatus` and avoid having instances
        /// where the first uploaded non-enacted determination (i.e., "suggested"), lacks the "enacted" data.
        /*
         Task {
             async let lastEnactedDeterminationID = determinationStorage
                 .fetchLastDeterminationObjectID(predicate: NSPredicate.enactedDetermination) // Fetches objects not older than 30 minutes

             self.lastEnactedDetermination = await determinationStorage
                 .getOrefDeterminationNotYetUploadedToNightscout(lastEnactedDeterminationID)
         }
         */
        Task {
            self.lastEnactedDetermination = await determinationStorage.fetchLatestEnactedDetermination()
        }
    }

    private func subscribe() {
        _ = reachabilityManager.startListening(onQueue: processQueue) { status in
            debug(.nightscout, "Network status: \(status)")
        }
    }

    private func registerHandlers() {
        coreDataPublisher?
            .filterByEntityName("OrefDetermination")
            .sink { [weak self] objectIDs in
                guard let self = self else { return }

                // Now hop onto the background context's queue
                self.backgroundContext.perform {
                    do {
                        // Fetch only those determination objects
                        let request: NSFetchRequest<OrefDetermination> = OrefDetermination.fetchRequest()
                        request.predicate = NSPredicate(format: "SELF IN %@", objectIDs)
                        let results = try self.backgroundContext.fetch(request)

                        // Safely filter out anything that's deleted or already uploaded
                        let unuploaded = results.filter { !$0.isDeleted && !$0.isUploadedToNS }

                        // If valid, proceed to send to subject for further processing
                        if !unuploaded.isEmpty {
                            self.orefDeterminationSubject.send()
                        }
                    } catch {
                        debugPrint("Failed to fetch OrefDetermination objects: \(error)")
                    }
                }
            }
            .store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("OverrideStored").sink { [weak self] _ in
            self?.uploadOverridesSubject.send()
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("OverrideRunStored").sink { [weak self] _ in
            self?.uploadOverridesSubject.send()
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("TempTargetStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task.detached {
                await self.uploadTempTargets()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("TempTargetRunStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task.detached {
                await self.uploadTempTargets()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("PumpEventStored")
            .sink { [weak self] objectIDs in
                guard let self = self else { return }

                // Now hop onto the background context’s queue
                self.backgroundContext.perform {
                    do {
                        let request: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
                        request.predicate = NSPredicate(format: "SELF IN %@", objectIDs)
                        let results = try self.backgroundContext.fetch(request)

                        // Safely filter out anything that’s deleted or already uploaded
                        let unuploaded = results.filter { !$0.isDeleted && !$0.isUploadedToNS }

                        // If valid, proceed to send to subject for further processing
                        if !unuploaded.isEmpty {
                            self.uploadPumpHistorySubject.send()
                        }
                    } catch {
                        debugPrint("Failed to fetch PumpEventStored objects: \(error)")
                    }
                }
            }
            .store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("CarbEntryStored")
            .sink { [weak self] objectIDs in
                guard let self = self else { return }

                // Now hop onto the background context’s queue
                self.backgroundContext.perform {
                    do {
                        let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
                        request.predicate = NSPredicate(format: "SELF IN %@", objectIDs)
                        let results = try self.backgroundContext.fetch(request)

                        // Safely filter out anything that’s deleted or already uploaded
                        let unuploaded = results.filter { !$0.isDeleted && !$0.isUploadedToNS }

                        // If valid, proceed to send to subject for further processing
                        if !unuploaded.isEmpty {
                            self.uploadCarbsSubject.send()
                        }
                    } catch {
                        debugPrint("Failed to fetch CarbEntryStored objects: \(error)")
                    }
                }
            }
            .store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("GlucoseStored")
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task.detached {
                    await self.uploadManualGlucose()
                }
            }
            .store(in: &subscriptions)
    }

    func registerSubscribers() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.uploadGlucose()
                }
            }
            .store(in: &subscriptions)

        /// We add debouncing behavior here for two main reasons
        /// 1. To ensure that any upload flag updates have properly been performed, and in subsequent fetching processes only truly unuploaded data is fetched
        /// 2. To not spam the user's NS site with a high number of uploads in a very short amount of time (less than 1sec)
        orefDeterminationSubject
            .debounce(for: .seconds(1), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] in
                guard let self = self else { return }
                Task {
                    await self.uploadDeviceStatus()
                }
            }
            .store(in: &subscriptions)

        uploadOverridesSubject
            .debounce(for: .seconds(2), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] in
                guard let self = self else { return }
                Task {
                    await self.uploadOverrides()
                }
            }
            .store(in: &subscriptions)

        uploadPumpHistorySubject
            .debounce(for: .seconds(2), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] in
                guard let self = self else { return }
                Task {
                    await self.uploadPumpHistory()
                }
            }
            .store(in: &subscriptions)

        uploadCarbsSubject
            .debounce(for: .seconds(2), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] in
                guard let self = self else { return }
                Task {
                    await self.uploadCarbs()
                }
            }
            .store(in: &subscriptions)
    }

    func setupNotification() {
        Foundation.NotificationCenter.default.publisher(for: .willUpdateOverrideConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.uploadOverrides()

                    // Post a notification indicating that the upload has finished and that we can end the background task in the OverridePresetsIntentRequest
                    Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
                }
            }
            .store(in: &subscriptions)

        Foundation.NotificationCenter.default.publisher(for: .willUpdateTempTargetConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.uploadTempTargets()

                    // Post a notification indicating that the upload has finished and that we can end the background task in the TempTargetPresetsIntentRequest
                    Foundation.NotificationCenter.default.post(name: .didUpdateTempTargetConfiguration, object: nil)
                }
            }
            .store(in: &subscriptions)
    }

    func sourceInfo() -> [String: Any]? {
        if let ping = ping {
            return [GlucoseSourceKey.nightscoutPing.rawValue: ping]
        }
        return nil
    }

    var cgmURL: URL? {
        if let url = settingsManager.settings.cgm.appURL {
            return url
        }

        let useLocal = settingsManager.settings.useLocalGlucoseSource

        let maybeNightscout = useLocal
            ? NightscoutAPI(url: URL(string: "http://127.0.0.1:\(settingsManager.settings.localGlucosePort)")!)
            : nightscoutAPI

        return maybeNightscout?.url
    }

    func fetchGlucose(since date: Date) async -> [BloodGlucose] {
        let useLocal = settingsManager.settings.useLocalGlucoseSource
        ping = nil

        if !useLocal {
            guard isNetworkReachable else {
                return []
            }
        }

        let maybeNightscout = useLocal
            ? NightscoutAPI(url: URL(string: "http://127.0.0.1:\(settingsManager.settings.localGlucosePort)")!)
            : nightscoutAPI

        guard let nightscout = maybeNightscout else {
            return []
        }

        let startDate = Date()

        do {
            let glucose = try await nightscout.fetchLastGlucose(sinceDate: date)
            if glucose.isNotEmpty {
                ping = Date().timeIntervalSince(startDate)
            }
            return glucose
        } catch {
            print(error.localizedDescription)
            return []
        }
    }

    // MARK: - GlucoseSource

    var glucoseManager: FetchGlucoseManager?
    var cgmManager: CGMManagerUI?

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Future { promise in
            Task {
                let glucoseData = await self.fetchGlucose(since: self.glucoseStorage.syncDate())
                promise(.success(glucoseData))
            }
        }
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }

    func fetchCarbs() async -> [CarbsEntry] {
        guard let nightscout = nightscoutAPI, isNetworkReachable, isDownloadEnabled else {
            return []
        }

        let since = carbsStorage.syncDate()
        do {
            let carbs = try await nightscout.fetchCarbs(sinceDate: since)
            return carbs
        } catch {
            debug(.nightscout, "Error fetching carbs: \(error.localizedDescription)")
            return []
        }
    }

    func fetchTempTargets() async -> [TempTarget] {
        guard let nightscout = nightscoutAPI, isNetworkReachable, isDownloadEnabled else {
            return []
        }

        let since = tempTargetsStorage.syncDate()
        do {
            let tempTargets = try await nightscout.fetchTempTargets(sinceDate: since)
            return tempTargets
        } catch {
            debug(.nightscout, "Error fetching temp targets: \(error.localizedDescription)")
            return []
        }
    }

    func deleteCarbs(withID id: String) async {
        guard let nightscout = nightscoutAPI, isUploadEnabled else { return }

        do {
            try await nightscout.deleteCarbs(withId: id)
            debug(.nightscout, "Carbs deleted")
        } catch {
            debug(
                .nightscout,
                "\(DebuggingIdentifiers.failed) Failed to delete Carbs from Nightscout with error: \(error.localizedDescription)"
            )
        }
    }

    func deleteInsulin(withID id: String) async {
        guard let nightscout = nightscoutAPI, isUploadEnabled else { return }

        do {
            try await nightscout.deleteInsulin(withId: id)
            debug(.nightscout, "Insulin deleted")
        } catch {
            debug(
                .nightscout,
                "\(DebuggingIdentifiers.failed) Failed to delete Insulin from Nightscout with error: \(error.localizedDescription)"
            )
        }
    }

    func deleteManualGlucose(withID id: String) async {
        guard let nightscout = nightscoutAPI, isUploadEnabled else { return }

        do {
            try await nightscout.deleteManualGlucose(withId: id)
        } catch {
            debug(
                .nightscout,
                "\(DebuggingIdentifiers.failed) Failed to delete Manual Glucose from Nightscout with error: \(error.localizedDescription)"
            )
        }
    }

    func deleteGlucose(withID id: String) async {
        guard let nightscout = nightscoutAPI, isUploadEnabled else { return }

        do {
            try await nightscout.deleteGlucose(withId: id)
        } catch {
            debug(
                .nightscout,
                "\(DebuggingIdentifiers.failed) Failed to delete CGM Glucose from Nightscout with error: \(error.localizedDescription)"
            )
        }
    }

    private func fetchBattery() async -> Battery {
        await backgroundContext.perform {
            do {
                let results = try self.backgroundContext.fetch(OpenAPS_Battery.fetch(NSPredicate.predicateFor30MinAgo))
                if let last = results.first {
                    let percent: Int? = Int(last.percent)
                    let voltage: Decimal? = last.voltage as Decimal?
                    let status: String? = last.status
                    let display: Bool? = last.display

                    if let status {
                        debugPrint(
                            "NightscoutManager: \(#function) \(DebuggingIdentifiers.succeeded) setup battery from core data successfully"
                        )
                        return Battery(
                            percent: percent,
                            voltage: voltage,
                            string: BatteryState(rawValue: status) ?? BatteryState.unknown,
                            display: display
                        )
                    }
                }
                debugPrint(
                    "NightscoutManager: \(#function) \(DebuggingIdentifiers.succeeded) successfully fetched; but no battery data available. Returning fallback default."
                )
                return Battery(percent: nil, voltage: nil, string: BatteryState.error, display: nil)
            } catch {
                debugPrint(
                    "NightscoutManager: \(#function) \(DebuggingIdentifiers.failed) failed to setup battery from core data"
                )
                return Battery(percent: nil, voltage: nil, string: BatteryState.error, display: nil)
            }
        }
    }

    /// Asynchronously uploads the current status to Nightscout, including OpenAPS status, pump status, and uploader details.
    ///
    /// This function gathers and processes various pieces of information such as the "enacted" and "suggested" determinations,
    /// pump battery and reservoir levels, insulin-on-board (IOB), and the uploader's battery status. It ensures that only
    /// valid determinations are uploaded by filtering out duplicates and handling unit conversions based on the user's
    /// settings. If the status upload is successful, it updates the determination storage to mark them as uploaded.
    ///
    /// Key steps:
    /// - Fetch the last unuploaded enacted and suggested determinations from the storage.
    /// - Retrieve pump-related data such as battery, reservoir, and status.
    /// - Parse determinations to ensure they are properly formatted for Nightscout, including unit conversions if needed.
    /// - Construct an `OpenAPSStatus` object with relevant information for upload.
    /// - Construct a `NightscoutStatus` object with all gathered data.
    /// - Attempt to upload the status to Nightscout. On success, update the storage to mark determinations as uploaded.
    /// - Schedule a task to upload pod age data separately.
    ///
    /// - Note: Ensure `nightscoutAPI` is initialized and `isUploadEnabled` is set to `true` before invoking this function.
    /// - Returns: Nothing.
    func uploadDeviceStatus() async {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            debug(.nightscout, "NS API not available or upload disabled. Aborting NS Status upload.")
            return
        }

        let oref2Data = await storage.retrieveAsync(OpenAPS.Monitor.oref2_variables, as: Oref2_variables.self)

        /*
         // For Suggested Determination, fetch the last un-uploaded one.
         async let suggestedDeterminationID = determinationStorage
             .fetchLastDeterminationObjectID(predicate: NSPredicate.suggestedDeterminationsNotYetUploadedToNightscout)
         */

        // For Suggested Determination, fetch the absolute newest one (ignoring isUploadedToNS)
        let fetchedSuggestedDetermination = await determinationStorage.fetchLatestSuggestedDetermination()

        // For Enacted Determination, always fetch the absolute latest record (regardless of upload status and age).
        let latestEnactedDetermination = await determinationStorage.fetchLatestEnactedDetermination()

        // OpenAPS Status
        async let fetchedBattery = fetchBattery()
        async let fetchedReservoir = Decimal(from: storage.retrieveRawAsync(OpenAPS.Monitor.reservoir) ?? "0")
        async let fetchedIOBEntry = storage.retrieveAsync(OpenAPS.Monitor.iob, as: [IOBEntry].self)
        async let fetchedPumpStatus = storage.retrieveAsync(OpenAPS.Monitor.status, as: PumpStatus.self)
        /*
         // Kör tester för parseReasonGlucoseValuesToMmolL i debug-läge om enheter är mmol/L
         #if DEBUG
             if settingsManager.settings.units == .mmolL {
                 await testParseReasonGlucoseValuesToMmolL()
             }
         #endif
         */
        /*
         // Retrieve the full Suggested Determination object from its ID.
         let fetchedSuggestedDetermination = await determinationStorage
             .getOrefDeterminationNotYetUploadedToNightscout(suggestedDeterminationID)
         */
        // (Using the above new method, we already have the absolute newest suggested determination.)

        // Guard: if both suggested and enacted are nil, abort.
        guard latestEnactedDetermination != nil || fetchedSuggestedDetermination != nil else {
            debug(
                .nightscout,
                "Both latestEnactedDetermination and fetchedSuggestedDetermination are nil. Aborting NS Status upload."
            )
            return
        }

        // Unwrap fetchedSuggestedDetermination and manipulate the timestamp field to ensure deliverAt and timestamp for a suggestion truly match!
        var modifiedSuggestedDetermination = fetchedSuggestedDetermination
        if var suggestion = fetchedSuggestedDetermination {
            suggestion.timestamp = suggestion.deliverAt

            if settingsManager.settings.units == .mmolL {
                suggestion.reason = parseReasonGlucoseValuesToMmolL(suggestion.reason)
                // TODO: verify that these parsings are needed for 3rd party apps, e.g., LoopFollow
                suggestion.current_target = suggestion.current_target?.asMmolL
                suggestion.minGuardBG = suggestion.minGuardBG?.asMmolL
                suggestion.minPredBG = suggestion.minPredBG?.asMmolL
                suggestion.threshold = suggestion.threshold?.asMmolL
            }
            // Check whether the last suggestion that was uploaded is the same that is fetched again when we are attempting to upload the enacted determination
            // Apparently we are too fast; so the flag update is not fast enough to have the predicate filter last suggestion out
            // If this check is truthy, set suggestion to nil so it's not uploaded again
            if let latestSuggested = lastSuggestedDetermination, latestSuggested.deliverAt == suggestion.deliverAt {
                modifiedSuggestedDetermination = nil
            } else {
                modifiedSuggestedDetermination = suggestion
            }
        }

        // Process the Enacted Determination (unit conversion if needed).
        var processedEnactedDetermination = latestEnactedDetermination
        if let enacted = latestEnactedDetermination, settingsManager.settings.units == .mmolL {
            var modifiedEnacted = enacted
            modifiedEnacted.reason = parseReasonGlucoseValuesToMmolL(enacted.reason)
            modifiedEnacted.current_target = enacted.current_target?.asMmolL
            modifiedEnacted.minGuardBG = enacted.minGuardBG?.asMmolL
            modifiedEnacted.minPredBG = enacted.minPredBG?.asMmolL
            modifiedEnacted.threshold = enacted.threshold?.asMmolL
            processedEnactedDetermination = modifiedEnacted
        }

        // Gather all relevant data for OpenAPS Status
        let iob = await fetchedIOBEntry
        let suggestedToUpload = modifiedSuggestedDetermination ?? lastSuggestedDetermination
        var enactedToUpload: Determination?

        if let latest = latestEnactedDetermination {
            // Extract properties into mutable variables.
            var reason = latest.reason
            var current_target = latest.current_target
            var minGuardBG = latest.minGuardBG
            var minPredBG = latest.minPredBG
            var threshold = latest.threshold
            var received = latest.received

            // Apply mmol conversions if needed.
            if settingsManager.settings.units == .mmolL {
                reason = parseReasonGlucoseValuesToMmolL(latest.reason)
                current_target = latest.current_target?.asMmolL
                minGuardBG = latest.minGuardBG?.asMmolL
                minPredBG = latest.minPredBG?.asMmolL
                threshold = latest.threshold?.asMmolL
            }

            if let suggestedDeliverAt = suggestedToUpload?.deliverAt,
               let latestDeliverAt = latest.deliverAt
            {
                let diff = suggestedDeliverAt.timeIntervalSince(latestDeliverAt)
                debug(.nightscout, "Enacted deliverAt vs suggested deliverAt diff is \(diff) seconds")

                // If the difference is less than 240 seconds (4 minutes), we consider the enacted status "fresh"
                // so set received to true.
                // Otherwise, if the enacted deliverAt is 240 seconds or more older, set it to false to make NS show X Not enacted.
                if diff < 240 {
                    received = true
                    debug(.nightscout, "Enacted deliverAt < 4 min older than suggested deliverAt -> enacted.received set to true")
                } else {
                    received = nil
                    debug(.nightscout, "Enacted deliverAt > 4 min older than suggested deliverAt -> enacted.received set to nil")
                }
            }

            // Create a new Determination instance with the modified values.
            enactedToUpload = Determination(
                id: latest.id,
                reason: reason,
                units: latest.units,
                insulinReq: latest.insulinReq,
                eventualBG: latest.eventualBG,
                sensitivityRatio: latest.sensitivityRatio,
                rate: latest.rate,
                duration: latest.duration,
                iob: latest.iob,
                cob: latest.cob,
                predictions: latest.predictions,
                deliverAt: latest.deliverAt,
                carbsReq: latest.carbsReq,
                temp: latest.temp,
                bg: latest.bg,
                reservoir: latest.reservoir,
                isf: latest.isf,
                timestamp: latest.timestamp,
                tdd: latest.tdd,
                insulin: latest.insulin,
                current_target: current_target,
                insulinForManualBolus: latest.insulinForManualBolus,
                manualBolusErrorString: latest.manualBolusErrorString,
                minDelta: latest.minDelta,
                expectedDelta: latest.expectedDelta,
                minGuardBG: minGuardBG,
                minPredBG: minPredBG,
                threshold: threshold,
                carbRatio: latest.carbRatio,
                received: received
            )
        }

        let openapsStatus = OpenAPSStatus(
            iob: iob?.first,
            suggested: suggestedToUpload,
            enacted: settingsManager.settings.closedLoop ? enactedToUpload : nil,
            version: Bundle.main.releaseVersionNumber ?? "Unknown"
        )

        // Daniel: Minska loggning // debug(.nightscout, "To be uploaded openapsStatus: \(openapsStatus)")

        // Gather all relevant data for NS Status
        let battery = await fetchedBattery
        let reservoir = await fetchedReservoir
        let pumpStatus = await fetchedPumpStatus
        let pump = NSPumpStatus(
            clock: pumpStatus?.timestamp ?? Date().addingTimeInterval(-3600),
            // Daniel: Fix to show correct timestamp in NS pump pill
            battery: battery,
            reservoir: reservoir != 0xDEAD_BEEF ? reservoir : nil,
            status: pumpStatus
        )

        let batteryLevel = await UIDevice.current.batteryLevel
        let batteryState = await UIDevice.current.batteryState
        let uploader = Uploader(
            batteryVoltage: nil,
            battery: Int(batteryLevel * 100),
            isCharging: batteryState == .charging || batteryState == .full
        )
        let userPreferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
        let additionalInfo: [String: Decimal] = [
            "maxSMBBasalMinutes": userPreferences?.maxSMBBasalMinutes ?? 30,
            "maxUAMSMBBasalMinutes": userPreferences?.maxUAMSMBBasalMinutes ?? 30,
            "autosensMax": userPreferences?.autosensMax ?? 1.2,
            "autosensMin": userPreferences?.autosensMin ?? 0.7
        ]

        // Daniel: Minska loggning // debug(.nightscout, "Additional Info: \(additionalInfo)")

        let status = NightscoutStatus(
            device: NightscoutTreatment.local,
            openaps: openapsStatus,
            pump: pump,
            uploader: uploader,
            additional: additionalInfo,
            oref2: oref2Data
        )

        do {
            try await nightscout.uploadDeviceStatus(status)
            // Daniel: Minska loggning // debug(.nightscout, "NSDeviceStatus with Determination uploaded")

            // Mark the suggested determination as uploaded.
            if let suggested = fetchedSuggestedDetermination {
                await updateOrefDeterminationAsUploaded([suggested])
                // Daniel: Minska loggning // debug(.nightscout, "Flagged last fetched suggested determination as uploaded")
            }

            // Mark the enacted determination as uploaded (if available).
            if let enacted = latestEnactedDetermination {
                await updateOrefDeterminationAsUploaded([enacted])
                // Daniel: Minska loggning // debug(.nightscout, "Flagged latest enacted determination as uploaded")
            }

            // Update local caches.
            if let parsedSuggested = modifiedSuggestedDetermination {
                lastSuggestedDetermination = parsedSuggested
            }
            if let latestEnacted = processedEnactedDetermination {
                lastEnactedDetermination = latestEnacted
            }
        } catch {
            debug(.nightscout, error.localizedDescription)
        }

        Task.detached {
            await self.uploadPodAge()
        }
    }

    private func updateOrefDeterminationAsUploaded(_ determination: [Determination]) async {
        await backgroundContext.perform {
            let ids = determination.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<OrefDetermination> = OrefDetermination.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    func uploadPodAge() async {
        let uploadedPodAge = storage.retrieve(OpenAPS.Nightscout.uploadedPodAge, as: [NightscoutTreatment].self) ?? []
        if let podAge = storage.retrieve(OpenAPS.Monitor.podAge, as: Date.self),
           uploadedPodAge.last?.createdAt == nil || podAge != uploadedPodAge.last!.createdAt!
        {
            let siteTreatment = NightscoutTreatment(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsSiteChange,
                createdAt: podAge,
                enteredBy: NightscoutTreatment.local,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                fat: nil,
                protein: nil,
                targetTop: nil,
                targetBottom: nil
            )
            await uploadNonCoreDataTreatments([siteTreatment])
        }
    }

    func uploadProfiles(alsoUploadNote: Bool = false, note: String = "Profilinställningar uppdaterades") async {
        if isUploadEnabled {
            do {
                guard let sensitivities = await storage.retrieveAsync(
                    OpenAPS.Settings.insulinSensitivities,
                    as: InsulinSensitivities.self
                ) else {
                    debug(.nightscout, "NightscoutManager uploadProfile: error loading insulinSensitivities")
                    return
                }
                guard let targets = await storage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self) else {
                    debug(.nightscout, "NightscoutManager uploadProfile: error loading bgTargets")
                    return
                }
                guard let carbRatios = await storage.retrieveAsync(OpenAPS.Settings.carbRatios, as: CarbRatios.self) else {
                    debug(.nightscout, "NightscoutManager uploadProfile: error loading carbRatios")
                    return
                }
                guard let basalProfile = await storage.retrieveAsync(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                else {
                    debug(.nightscout, "NightscoutManager uploadProfile: error loading basalProfile")
                    return
                }

                let shouldParseToMmolL = settingsManager.settings.units == .mmolL

                let sens = sensitivities.sensitivities.map { item in
                    NightscoutTimevalue(
                        time: String(item.start.prefix(5)),
                        value: !shouldParseToMmolL ? item.sensitivity : item.sensitivity.asMmolL,
                        timeAsSeconds: item.offset * 60
                    )
                }
                let targetLow = targets.targets.map { item in
                    NightscoutTimevalue(
                        time: String(item.start.prefix(5)),
                        value: !shouldParseToMmolL ? item.low : item.low.asMmolL,
                        timeAsSeconds: item.offset * 60
                    )
                }
                let targetHigh = targets.targets.map { item in
                    NightscoutTimevalue(
                        time: String(item.start.prefix(5)),
                        value: !shouldParseToMmolL ? item.high : item.high.asMmolL,
                        timeAsSeconds: item.offset * 60
                    )
                }
                let cr = carbRatios.schedule.map { item in
                    NightscoutTimevalue(
                        time: String(item.start.prefix(5)),
                        value: item.ratio,
                        timeAsSeconds: item.offset * 60
                    )
                }
                let basal = basalProfile.map { item in
                    NightscoutTimevalue(
                        time: String(item.start.prefix(5)),
                        value: item.rate,
                        timeAsSeconds: item.minutes * 60
                    )
                }

                let nsUnits: String = {
                    switch settingsManager.settings.units {
                    case .mgdL:
                        return "mg/dl"
                    case .mmolL:
                        return "mmol"
                    }
                }()

                var carbsHr: Decimal = 0
                var totalWeight: Decimal = 0

                // Extract all unique time offsets from both ISF and CR schedules
                var uniqueOffsets = Set(sensitivities.sensitivities.map(\.offset) + carbRatios.schedule.map(\.offset))
                    .sorted() // Sort by time in minutes

                // Ensure 1440 (24:00) is included as the last offset
                if !uniqueOffsets.contains(1440) {
                    uniqueOffsets.append(1440)
                }

                // debug(.nightscout, "Unique time offsets: \(uniqueOffsets)")

                // Iterate through each time segment (including the last hour)
                for (index, startOffset) in uniqueOffsets.enumerated() where index < uniqueOffsets.count - 1 {
                    let endOffset = uniqueOffsets[index + 1] // The next time point
                    let duration = Decimal(endOffset - startOffset) / 60 // Convert minutes to hours

                    // Get the closest ISF value that applies at this time
                    let isfEntry = sensitivities.sensitivities.last(where: { $0.offset <= startOffset })
                    let isf = isfEntry?.sensitivity ?? 0

                    // Get the closest CR value that applies at this time
                    let crEntry = carbRatios.schedule.last(where: { $0.offset <= startOffset })
                    let cr = crEntry?.ratio ?? 0

                    if isf > 0, cr > 0 {
                        let weightedImpact = settingsManager.preferences.min5mCarbimpact * 12 / isf * cr * duration
                        carbsHr += weightedImpact
                        totalWeight += duration

                        /* debug(
                             .nightscout,
                             "Time \(startOffset)-\(endOffset) min: ISF \(isf), CR \(cr), Duration \(duration) hr -> Weighted carbsHr impact: \(weightedImpact)"
                         ) */
                    }
                }

                // Normalize by total duration weight to get an average impact per hour
                if totalWeight > 0 {
                    carbsHr /= totalWeight
                }

                // Round the result to one decimal place
                carbsHr = Decimal(round(Double(carbsHr) * 10.0)) / 10

                // Daniel: Minska loggning // debug(.nightscout, "Final calculated carbsHr: \(carbsHr)")

                let scheduledProfile = ScheduledNightscoutProfile(
                    dia: settingsManager.pumpSettings.insulinActionCurve,
                    carbs_hr: Int(carbsHr),
                    delay: 0,
                    timezone: TimeZone.current.identifier,
                    target_low: targetLow,
                    target_high: targetHigh,
                    sens: sens,
                    basal: basal,
                    carbratio: cr,
                    units: nsUnits
                )
                let defaultProfile = "default"

                let preferences = NightscoutPreferences(preferences: settingsManager.preferences)

                let now = Date()

                let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
                let deviceToken = UserDefaults.standard.string(forKey: "deviceToken") ?? ""
                let isAPNSProduction = UserDefaults.standard.bool(forKey: "isAPNSProduction")
                let presetOverrides = await overridesStorage.getPresetOverridesForNightscout()
                let teamID = Bundle.main.object(forInfoDictionaryKey: "TeamID") as? String ?? ""
                let expireDate = BuildDetails.shared.calculateExpirationDate()

                let profileStore = NightscoutProfileStore(
                    defaultProfile: defaultProfile,
                    startDate: now,
                    mills: Int(now.timeIntervalSince1970) * 1000,
                    units: nsUnits,
                    enteredBy: NightscoutTreatment.local,
                    store: [defaultProfile: scheduledProfile],
                    bundleIdentifier: bundleIdentifier,
                    deviceToken: deviceToken,
                    isAPNSProduction: isAPNSProduction,
                    overridePresets: presetOverrides,
                    teamID: teamID,
                    preferences: preferences,
                    expirationDate: expireDate
                )

                guard let nightscout = nightscoutAPI, isNetworkReachable else {
                    if !isNetworkReachable {
                        debug(.nightscout, "Network issues; aborting upload")
                    }
                    debug(.nightscout, "Nightscout API service not available; aborting upload")
                    return
                }

                do {
                    try await nightscout.uploadProfile(profileStore)

                    BuildDetails.shared.recordUploadedExpireDate(expireDate: expireDate)

                    // Daniel: Minska loggning // debug(.nightscout, "Profile uploaded")

                    // If alsoUploadNote is true, call the uploadNoteTreatment function with the provided note
                    if alsoUploadNote {
                        await uploadNoteTreatment(note: note)
                    }
                } catch {
                    debug(.nightscout, "NightscoutManager uploadProfile: \(error.localizedDescription)")
                }
            }
        } else {
            debug(.nightscout, "Upload to NS disabled; aborting profile uploaded")
        }
    }

    func importSettings() async -> ScheduledNightscoutProfile? {
        guard let nightscout = nightscoutAPI else {
            debug(.nightscout, "NS API not available. Aborting NS Status upload.")
            return nil
        }

        do {
            return try await nightscout.importSettings()
        } catch {
            debug(.nightscout, error.localizedDescription)
            return nil
        }
    }

    func uploadGlucose() async {
        let glucose = await glucoseStorage.getGlucoseNotYetUploadedToNightscout()

        async let nightscoutUpload: Void = uploadGlucose(glucose)
        async let localUpload: Void = uploadGlucoseLocallyIfNeeded(glucose)

        _ = await (nightscoutUpload, localUpload)

        await uploadNonCoreDataTreatments(glucoseStorage.getCGMStateNotYetUploadedToNightscout())
    }

    private var isLocalGlucoseUploadEnabled: Bool {
        if UserDefaults.standard.object(forKey: "HomeAssistantConfig.localGlucoseUploadEnabled") == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: "HomeAssistantConfig.localGlucoseUploadEnabled")
    }

    private var localHomeAssistantWebhookURL: URL? {
        let urlString =
            UserDefaults.standard.string(forKey: "HomeAssistantConfig.urlHA")?.nonEmpty
                ?? "http://192.168.0.191:8123/api/webhook/localglucoseupdate"

        return URL(string: urlString)
    }

    private var localThisPhoneIPAddress: String {
        UserDefaults.standard.string(forKey: "HomeAssistantConfig.urlThisPhone")?.nonEmpty
            ?? "192.168.0.246"
    }

    private var isConnectedToConfiguredLocalWiFi: Bool {
        currentWiFiIPv4Address == localThisPhoneIPAddress
    }

    private func uploadGlucoseLocallyIfNeeded(_ glucose: [BloodGlucose]) async {
        guard !glucose.isEmpty else { return }

        guard isLocalGlucoseUploadEnabled else {
            return
        }

        guard isConnectedToConfiguredLocalWiFi else {
            debug(
                .nightscout,
                "Local glucose not uploaded - current Wi-Fi IP: \(currentWiFiIPv4Address ?? "none"), expected: \(localThisPhoneIPAddress)"
            )
            return
        }

        do {
            try await uploadLatestGlucoseToLocalWebhook(glucose)
        } catch {
            debug(.nightscout, "Local glucose upload failed: \(error.localizedDescription)")
        }
    }

    private func uploadLatestGlucoseToLocalWebhook(_ glucose: [BloodGlucose]) async throws {
        guard let latestGlucose = glucose
            .filter({ $0.glucose != nil })
            .max(by: { $0.date < $1.date }),
            let glucoseValue = latestGlucose.glucose
        else {
            debug(.nightscout, "No local glucose value available to upload")
            return
        }

        struct LocalGlucosePayload: Encodable {
            let glucose: Int
            let date: Decimal
        }

        guard let url = localHomeAssistantWebhookURL else {
            throw URLError(.badURL)
        }

        let payload = LocalGlucosePayload(
            glucose: glucoseValue,
            date: latestGlucose.date
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.allowsCellularAccess = false
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.encoder.encode(payload)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4

        let session = URLSession(configuration: configuration)
        defer {
            session.finishTasksAndInvalidate()
        }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            debug(.nightscout, "Local glucose upload failed with HTTP status: \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        debug(.nightscout, "Local glucose upload successful: \(glucoseValue) mg/dL, date: \(latestGlucose.date)")
    }

    func uploadManualGlucose() async {
        await uploadManualGlucose(glucoseStorage.getManualGlucoseNotYetUploadedToNightscout())
    }

    /*
     func uploadPumpHistory() async {
         await uploadPumpHistory(pumpHistoryStorage.getPumpHistoryNotYetUploadedToNightscout())
     }
     */

    // MARK: - Upload: Pump History with Deduplication

    func uploadPumpHistory() async {
        let allTreatments = await pumpHistoryStorage.getPumpHistoryNotYetUploadedToNightscout(using: backgroundContext)
        debugPrint("Total treatments fetched for upload: \(allTreatments.count)")

        // Group by `id + createdAt` to detect duplicates
        var treatmentGroups: [String: [NightscoutTreatment]] = [:]
        for treatment in allTreatments {
            let key = "\(treatment.id ?? "")-\((treatment.createdAt ?? .distantPast).timeIntervalSince1970)"
            treatmentGroups[key, default: []].append(treatment)
        }

        // Extract the unique treatment to upload
        let uniqueTreatments = treatmentGroups.values.compactMap { group -> NightscoutTreatment? in
            if group.count > 1 {
                debugPrint("⚠️ Duplicate treatments detected and filtered out: \(group.map { $0.id ?? "nil" })")
            }
            return group.first
        }

        debugPrint("Unique treatments after filtering: \(uniqueTreatments.count)")

        guard !uniqueTreatments.isEmpty,
              let nightscout = nightscoutAPI,
              isUploadEnabled
        else {
            return
        }

        do {
            for chunk in uniqueTreatments.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            // Flatten all treatments in all duplicate groups to be marked as uploaded
            let allToMarkAsUploaded = treatmentGroups.values.flatMap { $0 }
            await updatePumpEventStoredsAsUploaded(allToMarkAsUploaded)

            // Daniel: Minska loggning // debug(.nightscout, "✅ Pump treatments uploaded (including duplicates marked as uploaded)")
        } catch {
            debug(.nightscout, "❌ Failed to upload pump treatments: \(error.localizedDescription)")
            // Don't mark anything as uploaded if upload failed
        }
    }

    func uploadCarbs() async {
        await uploadCarbs(carbsStorage.getCarbsNotYetUploadedToNightscout())
        await uploadCarbs(carbsStorage.getFPUsNotYetUploadedToNightscout())
    }

    func uploadOverrides() async {
        await uploadOverrides(overridesStorage.getOverridesNotYetUploadedToNightscout())
        await uploadOverrideRuns(overridesStorage.getOverrideRunsNotYetUploadedToNightscout())
    }

    func uploadTempTargets() async {
        await uploadTempTargets(await tempTargetsStorage.getTempTargetsNotYetUploadedToNightscout())
        await uploadTempTargetRuns(await tempTargetsStorage.getTempTargetRunsNotYetUploadedToNightscout())
    }

    private func uploadGlucose(_ glucose: [BloodGlucose]) async {
        guard !glucose.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled, isUploadGlucoseEnabled else {
            return
        }

        do {
            // Upload in Batches of 100
            for chunk in glucose.chunks(ofCount: 100) {
                try await nightscout.uploadGlucose(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the GlucoseStored objects
            await updateGlucoseAsUploaded(glucose)

            // Daniel: Minska loggning // debug(.nightscout, "Glucose uploaded")
        } catch {
            debug(.nightscout, "Upload of glucose failed: \(error.localizedDescription)")
        }
    }

    private func updateGlucoseAsUploaded(_ glucose: [BloodGlucose]) async {
        await backgroundContext.perform {
            let ids = glucose.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadNonCoreDataTreatments(_ treatments: [NightscoutTreatment]) async {
        guard !treatments.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            for chunk in treatments.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            // Daniel: Minska loggning // debug(.nightscout, "Treatments uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    // Daniel: Added to upload bolus failure reasons as a note to Nightscout
    internal func uploadErrors(withNotes notes: String) async {
        let errorNote = NightscoutTreatment(
            duration: nil,
            rawDuration: nil,
            rawRate: nil,
            absolute: nil,
            rate: nil,
            eventType: .nsNote,
            createdAt: Date(),
            enteredBy: NightscoutTreatment.local,
            bolus: nil,
            insulin: nil,
            notes: notes,
            carbs: nil,
            fat: nil,
            protein: nil,
            targetTop: nil,
            targetBottom: nil
        )
        guard let nightscout = nightscoutAPI, isNetworkReachable, isErrorUploadEnabled else {
            if !isNetworkReachable {
                debug(.nightscout, "Network issues; aborting upload of bolus error note")
            }
            debug(.nightscout, "Nightscout API service not available; aborting upload of bolus error note")
            return
        }
        do {
            try await nightscout.uploadErrors(errorNote)
            debug(.nightscout, "Error note uploaded successfully.")
        } catch {
            debug(.nightscout, "Failed to upload error note: \(error.localizedDescription)")
        }
    }

    /*
     private func uploadPumpHistory(_ treatments: [NightscoutTreatment]) async {
         guard !treatments.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
             return
         }

         do {
             for chunk in treatments.chunks(ofCount: 100) {
                 try await nightscout.uploadTreatments(Array(chunk))
             }

             await updatePumpEventStoredsAsUploaded(treatments)

             debug(.nightscout, "Treatments uploaded")
         } catch {
             debug(.nightscout, error.localizedDescription)
         }
     }
     */

    private func updatePumpEventStoredsAsUploaded(_ treatments: [NightscoutTreatment]) async {
        await backgroundContext.perform {
            let ids = treatments.compactMap(\.id)
            debugPrint("🟡 Attempting to mark as uploaded. IDs: \(ids)")

            let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids as NSArray)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                debugPrint("🔵 Found \(results.count) PumpEventStored entries matching IDs")
                debugPrint("🔍 Fetched IDs: \(results.compactMap(\.id))")

                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else {
                    debugPrint("⚠️ No changes to save in background context — nothing marked as uploaded.")
                    return
                }

                try self.backgroundContext.save()
                debugPrint("✅ Successfully saved isUploadedToNS updates for pump events.")
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadManualGlucose(_ treatments: [NightscoutTreatment]) async {
        guard !treatments.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            for chunk in treatments.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the GlucoseStored objects
            await updateManualGlucoseAsUploaded(treatments)

            // Daniel: Minska loggning // debug(.nightscout, "Treatments uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    private func updateManualGlucoseAsUploaded(_ treatments: [NightscoutTreatment]) async {
        await backgroundContext.perform {
            let ids = treatments.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadCarbs(_ treatments: [NightscoutTreatment]) async {
        guard !treatments.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            for chunk in treatments.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the CarbEntryStored objects
            await updateCarbsAsUploaded(treatments)

            // Daniel: Minska loggning // debug(.nightscout, "Treatments uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    private func updateCarbsAsUploaded(_ treatments: [NightscoutTreatment]) async {
        await backgroundContext.perform {
            let ids = treatments.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadOverrides(_ overrides: [NightscoutExercise]) async {
        guard !overrides.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }
        do {
            var processedOverrides: [NightscoutExercise] = []
            for override in overrides {
                guard let createdAtString = override.created_at as? String else {
                    continue
                }

                // Check for an existing stored override and delete if needed (This is neccessary to delete original entry in NS when a running override gets customized with a new duration).
                try await overridesStorage.checkIfShouldDeleteNightscoutOverrideEntry(
                    forCreatedAt: createdAtString,
                    newDuration: override.duration,
                    using: nightscout
                )

                try await nightscout.uploadOverrides([override])

                processedOverrides.append(override)
            }

            for chunk in processedOverrides.chunks(ofCount: 100) {
                try await nightscout.uploadOverrides(Array(chunk))
            }

            await updateOverridesAsUploaded(overrides)
            // Daniel: Minska loggning // debug(.nightscout, "All overrides processed and marked as uploaded")
        } catch {
            debug(.nightscout, "Error during override upload process: \(error.localizedDescription)")
        }
    }

    private func updateOverridesAsUploaded(_ overrides: [NightscoutExercise]) async {
        await backgroundContext.perform {
            let ids = overrides.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadOverrideRuns(_ overrideRuns: [NightscoutExercise]) async {
        guard !overrideRuns.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            var processedOverrideRuns: [NightscoutExercise] = []
            for overrideRun in overrideRuns {
                guard let createdAtString = overrideRun.created_at as? String else {
                    continue
                }

                // Check for an existing stored override and delete if needed
                // This is neccessary when a running override is cancelled, or replaced with a new override, before its duration is over.
                try await overridesStorage.checkIfShouldDeleteNightscoutOverrideEntry(
                    forCreatedAt: createdAtString,
                    newDuration: overrideRun.duration,
                    using: nightscout
                )

                processedOverrideRuns.append(overrideRun)
            }

            for chunk in processedOverrideRuns.chunks(ofCount: 100) {
                try await nightscout.uploadOverrides(Array(chunk))
            }

            await updateOverrideRunsAsUploaded(overrideRuns)
            // Daniel: Minska loggning // debug(.nightscout, "All override runs processed and marked as uploaded")
        } catch {
            debug(.nightscout, "Error during override run upload process: \(error.localizedDescription)")
        }
    }

    private func updateOverrideRunsAsUploaded(_ overrideRuns: [NightscoutExercise]) async {
        await backgroundContext.perform {
            let ids = overrideRuns.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<OverrideRunStored> = OverrideRunStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadTempTargets(_ tempTargets: [NightscoutTreatment]) async {
        guard !tempTargets.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            for chunk in tempTargets.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the TempTargetStored objects
            await updateTempTargetsAsUploaded(tempTargets)

            // Daniel: Minska loggning // debug(.nightscout, "Temp Targets uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    private func updateTempTargetsAsUploaded(_ tempTargets: [NightscoutTreatment]) async {
        await backgroundContext.perform {
            let ids = tempTargets.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS for TempTargetStored: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadTempTargetRuns(_ tempTargetRuns: [NightscoutTreatment]) async {
        guard !tempTargetRuns.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            for chunk in tempTargetRuns.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the TempTargetRunStored objects
            await updateTempTargetRunsAsUploaded(tempTargetRuns)

            // Daniel: Minska loggning // debug(.nightscout, "Temp Target Runs uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    private func updateTempTargetRunsAsUploaded(_ tempTargetRuns: [NightscoutTreatment]) async {
        await backgroundContext.perform {
            let ids = tempTargetRuns.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<TempTargetRunStored> = TempTargetRunStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS for TempTargetRunStored: \(error.userInfo)"
                )
            }
        }
    }

    // TODO: have this checked; this has never actually written anything to file; the entire logic of this function seems broken
    func uploadNoteTreatment(note: String) async {
        let uploadedNotes = storage.retrieve(OpenAPS.Nightscout.uploadedNotes, as: [NightscoutTreatment].self) ?? []
        let now = Date()

        if uploadedNotes.last?.notes != note || (uploadedNotes.last?.createdAt ?? .distantPast) != now {
            let noteTreatment = NightscoutTreatment(
                eventType: .nsNote,
                createdAt: now,
                enteredBy: NightscoutTreatment.local,
                notes: note,
                targetTop: nil,
                targetBottom: nil
            )
            await uploadNonCoreDataTreatments([noteTreatment])
            // TODO: fix/adjust, if necessary
//            await uploadTreatments([noteTreatment], fileToSave: OpenAPS.Nightscout.uploadedNotes)
        }
    }
}

extension Array {
    func chunks(ofCount count: Int) -> [[Element]] {
        stride(from: 0, to: self.count, by: count).map {
            Array(self[$0 ..< Swift.min($0 + count, self.count)])
        }
    }
}

extension BaseNightscoutManager {
    /**
     Converts glucose-related values in the given `reason` string to mmol/L, including ranges (e.g., `ISF: 54→54`), comparisons (e.g., `maxDelta 37 > 20% of BG 95`), and both positive and negative values (e.g., `Dev: -36`).

     - Parameters:
       - reason: The string containing glucose-related values to be converted.

     - Returns:
       A string with glucose values converted to mmol/L.

     - Glucose tags handled: `ISF:`, `Target:`, `minPredBG`, `minGuardBG`, `IOBpredBG`, `COBpredBG`, `UAMpredBG`, `Dev:`, `maxDelta`, `BGI`.
     */

    // TODO: Consolidate all mmol parsing methods (in TagCloudView, NightscoutManager and HomeRootView) to one central func
    func parseReasonGlucoseValuesToMmolL(_ reason: String) -> String {
        // Normalize HTML entities to standard comparison symbols
        let normalizedReason = reason
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        // Rearranged pattern array with specialized "Eventual BG ... but Min. Delta ... < Exp. Delta ..." first.
        let patterns = [
            // 0. Specialized case for "Eventual BG … but Min. Delta … < Exp. Delta …"
            "Eventual BG\\s*-?\\d+\\s*>\\s*-?\\d+\\s*but\\s*Min\\.\\s*Delta\\s*-?\\d+\\.?\\d{0,2}\\s*<\\s*Exp\\.\\s*Delta\\s*-?\\d+\\.?\\d{0,2}",
            // 1. New case for "minDelta X>expectedDelta Y"  // NEW
            "and minDelta\\s+-?\\d+\\s*>\\s*expectedDelta\\s+-?\\d+",
            // 2. ISF or Mål with one or two arrows
            "(?:ISF|Mål):\\s*-?\\d+\\.?\\d*(?:→-?\\d+\\.?\\d*)+",
            // 3. Dev pattern
            "Dev:\\s*-?\\d+\\.?\\d*",
            // 4. BGI pattern
            "BGI:\\s*-?\\d+\\.?\\d*",
            // 5. Mål pattern
            "Mål:\\s*-?\\d+\\.?\\d*",
            // 6. Patterns for minPredBG, minGuardBG, etc.
            "(?:minPredBG|minGuardBG|IOBpredBG|COBpredBG|UAMpredBG)\\s+-?\\d+\\.?\\d*(?:<-?\\d+\\.?\\d*)?",
            // 7. minGuardBG x<y
            "minGuardBG\\s+-?\\d+\\.?\\d*<-?\\d+\\.?\\d*",
            // 8. Generic cases for Eventual BG with ≥
            "Eventual BG\\s+-?\\d+\\.?\\d*\\s*≥\\s*-?\\d+\\.?\\d*",
            // 9. Generic cases for Eventual BG with <
            "Eventual BG\\s+-?\\d+\\.?\\d*\\s*<\\s*-?\\d+\\.?\\d*",
            // 10. maxDelta x > y% of BG z
            "\\S+\\s+\\d+\\s*>\\s*\\d+%\\s+of\\s+BG\\s+\\d+",
            // 11. "in range" case, e.g., "105-80 inom mål"
            "-?\\d+\\.?\\d*-\\d+\\.?\\d* inom mål",
            // 12. maxDelta numeric pattern
            "maxDelta\\s+(\\d+)\\s*>\\s*(\\d+)%\\s+of\\s+BG\\s+(\\d+)"
        ]
        let pattern = patterns.joined(separator: "|")
        let regex = try! NSRegularExpression(pattern: pattern)

        func convertToMmolL(_ value: String) -> String {
            if let glucoseValue = Double(value.replacingOccurrences(of: "[^\\d.-]", with: "", options: .regularExpression)) {
                let mmolValue = Decimal(glucoseValue).asMmolL
                return mmolValue.description
            }
            return value
        }

        let matches = regex.matches(in: normalizedReason, range: NSRange(normalizedReason.startIndex..., in: normalizedReason))
        var updatedReason = normalizedReason

        for match in matches.reversed() {
            guard let range = Range(match.range, in: normalizedReason) else { continue }
            let glucoseValueString = String(normalizedReason[range])

            if glucoseValueString.contains(" inom mål") {
                // Handle "105-80 inom mål" from JavaScript: o(Gt,i)+"-"+o(Ct,i)+" inom mål"
                let regexSubPattern = #"(-?\d+\.?\d*)-(-?\d+\.?\d*)\s*inom\s+mål"#
                let subRegex = try! NSRegularExpression(pattern: regexSubPattern)

                if let subMatch = subRegex.firstMatch(
                    in: glucoseValueString,
                    range: NSRange(glucoseValueString.startIndex..., in: glucoseValueString)
                ) {
                    let firstValue = String(glucoseValueString[Range(subMatch.range(at: 1), in: glucoseValueString)!])
                    let secondValue = String(glucoseValueString[Range(subMatch.range(at: 2), in: glucoseValueString)!])

                    let formattedFirstValue = convertToMmolL(firstValue)
                    let formattedSecondValue = convertToMmolL(secondValue)

                    /* debug(
                         .nightscout,
                         "Konverterar 'inom mål': \(firstValue) → \(formattedFirstValue), \(secondValue) → \(formattedSecondValue)"
                     ) */

                    let formattedString = "\(formattedFirstValue)-\(formattedSecondValue) inom mål"
                    updatedReason.replaceSubrange(range, with: formattedString)
                } /* else {
                     debug(.nightscout, "⚠️ Kunde inte matcha 'inom mål'-mönster för: \(glucoseValueString)")
                 } */
            } else if glucoseValueString.contains("Eventual BG"),
                      glucoseValueString.contains("but Min. Delta"),
                      glucoseValueString.contains("Exp. Delta")
            {
                // Handle "Eventual BG X > Y but Min. Delta A < Exp. Delta B"
                let regexSubPattern =
                    #"Eventual BG\s*(-?\d+)\s*>\s*(-?\d+)\s*but\s*Min\. Delta\s*(-?\d+\.?\d{0,2})\s*<\s*Exp\. Delta\s*(-?\d+\.?\d{0,2})"#
                let subRegex = try! NSRegularExpression(pattern: regexSubPattern)

                if let subMatch = subRegex.firstMatch(
                    in: glucoseValueString,
                    range: NSRange(glucoseValueString.startIndex..., in: glucoseValueString)
                ) {
                    let bg1 = String(glucoseValueString[Range(subMatch.range(at: 1), in: glucoseValueString)!])
                    let bg2 = String(glucoseValueString[Range(subMatch.range(at: 2), in: glucoseValueString)!])
                    let minDelta = String(glucoseValueString[Range(subMatch.range(at: 3), in: glucoseValueString)!])
                    let expDelta = String(glucoseValueString[Range(subMatch.range(at: 4), in: glucoseValueString)!])

                    let formattedString =
                        "Prognos BG: \(convertToMmolL(bg1))>\(convertToMmolL(bg2)) men min delta \(convertToMmolL(minDelta)) mindre än exp delta \(convertToMmolL(expDelta))" // Tog bort < här eftersom den skapade ngt märkligt trunkeringsproblem i NS/MongoDB
                    updatedReason.replaceSubrange(range, with: formattedString)
                }
            } else if glucoseValueString.contains("minDelta"),
                      glucoseValueString.contains("expectedDelta")
            { // NEW
                // Handle "and minDelta X>expectedDelta Y"
                let regexSubPattern =
                    #"and minDelta\s*(-?\d+)\s*>\s*expectedDelta\s*(-?\d+)"#
                let subRegex = try! NSRegularExpression(pattern: regexSubPattern)

                if let subMatch = subRegex.firstMatch(
                    in: glucoseValueString,
                    range: NSRange(glucoseValueString.startIndex..., in: glucoseValueString)
                ) {
                    let minDelta = String(glucoseValueString[Range(subMatch.range(at: 1), in: glucoseValueString)!])
                    let expDelta = String(glucoseValueString[Range(subMatch.range(at: 2), in: glucoseValueString)!])

                    let formattedString =
                        "och min delta \(convertToMmolL(minDelta))>exp delta \(convertToMmolL(expDelta))"
                    updatedReason.replaceSubrange(range, with: formattedString)
                }
            } else if glucoseValueString.contains("→") {
                // Handle ISF: X→Y… or Mål: X→Y→Z…
                let parts = glucoseValueString.components(separatedBy: ":")
                guard parts.count == 2 else { continue }
                let targetOrISF = parts[0].trimmingCharacters(in: .whitespaces)
                let values = parts[1]
                    .components(separatedBy: "→")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let convertedValues = values.map { convertToMmolL($0) }
                let joined = convertedValues.joined(separator: "→")
                let rebuilt = "\(targetOrISF): \(joined)"
                updatedReason.replaceSubrange(range, with: rebuilt)
            } else if glucoseValueString.contains("Eventual BG"),
                      glucoseValueString.contains("<")
            {
                // Handle Eventual BG XX < target
                let parts = glucoseValueString.components(separatedBy: "<")
                if parts.count == 2 {
                    let bgPart = parts[0].replacingOccurrences(of: "Eventual BG", with: "").trimmingCharacters(in: .whitespaces)
                    let targetValue = parts[1].trimmingCharacters(in: .whitespaces)
                    let formattedBGPart = convertToMmolL(bgPart)
                    let formattedTargetValue = convertToMmolL(targetValue)
                    let formattedString = "Prognos BG: \(formattedBGPart)<\(formattedTargetValue)"
                    updatedReason.replaceSubrange(range, with: formattedString)
                }
            } else if glucoseValueString.contains("<") {
                // Handle minGuardBG (or minPredBG, etc.) x < y
                let parts = glucoseValueString.components(separatedBy: "<")
                if parts.count == 2 {
                    let firstValue = parts[0].trimmingCharacters(in: .whitespaces)
                    let secondValue = parts[1].trimmingCharacters(in: .whitespaces)
                    let formattedFirstValue = convertToMmolL(firstValue)
                    let formattedSecondValue = convertToMmolL(secondValue)
                    let formattedString = "minGuardBG \(formattedFirstValue)<\(formattedSecondValue)"
                    updatedReason.replaceSubrange(range, with: formattedString)
                }
            } else if glucoseValueString.contains("≥") {
                // Handle "Eventual BG X >= Y"
                let eventBGPattern = #"Eventual BG\s*(-?\d+(?:\.\d+)?)\s*≥\s*(-?\d+(?:\.\d+)?)"#
                let eventBGRegex = try! NSRegularExpression(pattern: eventBGPattern)
                if let eventBGMatch = eventBGRegex.firstMatch(
                    in: glucoseValueString,
                    range: NSRange(glucoseValueString.startIndex..., in: glucoseValueString)
                ) {
                    let bgValue = String(glucoseValueString[Range(eventBGMatch.range(at: 1), in: glucoseValueString)!])
                    let targetValue = String(glucoseValueString[Range(eventBGMatch.range(at: 2), in: glucoseValueString)!])
                    let formattedBG = convertToMmolL(bgValue)
                    let formattedTarget = convertToMmolL(targetValue)
                    let formattedString = "Prognos BG: \(formattedBG)≥\(formattedTarget)"
                    updatedReason.replaceSubrange(range, with: formattedString)
                }
            } else if glucoseValueString.starts(with: "maxDelta") {
                // Handle "maxDelta 25 > 15% of BG 158"
                let pattern = "maxDelta\\s+(\\d+)\\s*>\\s*(\\d+)%\\s+of\\s+BG\\s+(\\d+)"
                let subRegex = try! NSRegularExpression(pattern: pattern)
                if let match = subRegex.firstMatch(
                    in: glucoseValueString,
                    range: NSRange(glucoseValueString.startIndex..., in: glucoseValueString)
                ), match.numberOfRanges == 4 {
                    let value1 = String(glucoseValueString[Range(match.range(at: 1), in: glucoseValueString)!])
                    let percentage = String(glucoseValueString[Range(match.range(at: 2), in: glucoseValueString)!])
                    let bg = String(glucoseValueString[Range(match.range(at: 3), in: glucoseValueString)!])
                    let formattedValue1 = convertToMmolL(value1)
                    let formattedBG = convertToMmolL(bg)
                    let formatted = "Max delta \(formattedValue1)>\(percentage)% av BG \(formattedBG)"
                    updatedReason.replaceSubrange(range, with: formatted)
                }
            } else if glucoseValueString.contains(">"), glucoseValueString.contains("BG") {
                // Handle "maxDelta 37 > 20% of BG 95" style
                let localPattern = "(\\d+) > (\\d+)% of BG (\\d+)"
                let localRegex = try! NSRegularExpression(pattern: localPattern)
                let localMatches = localRegex.matches(
                    in: glucoseValueString,
                    range: NSRange(glucoseValueString.startIndex..., in: glucoseValueString)
                )
                if let localMatch = localMatches.first, localMatch.numberOfRanges == 4 {
                    let range1 = Range(localMatch.range(at: 1), in: glucoseValueString)!
                    let range2 = Range(localMatch.range(at: 2), in: glucoseValueString)!
                    let range3 = Range(localMatch.range(at: 3), in: glucoseValueString)!
                    let firstValue = convertToMmolL(String(glucoseValueString[range1]))
                    let thirdValue = convertToMmolL(String(glucoseValueString[range3]))
                    let oldSnippet =
                        "\(glucoseValueString[range1])>\(glucoseValueString[range2])% of BG \(glucoseValueString[range3])"
                    let newSnippet = "\(firstValue)>\(glucoseValueString[range2])% of BG \(thirdValue)"
                    let replaced = glucoseValueString.replacingOccurrences(of: oldSnippet, with: newSnippet)
                    updatedReason.replaceSubrange(range, with: replaced)
                }
            } else {
                // Handle everything else, e.g. "minPredBG 39", etc.
                let parts = glucoseValueString.components(separatedBy: .whitespaces)
                if parts.count >= 2 {
                    var metric = parts[0]
                    let value = parts[1]
                    if !metric.hasSuffix(":") {
                        metric += ":"
                    }
                    let formattedValue = convertToMmolL(value)
                    let formattedString = "\(metric) \(formattedValue)"
                    updatedReason.replaceSubrange(range, with: formattedString)
                }
            }
        }
        return updatedReason
    }

    private func testParseReasonGlucoseValuesToMmolL() {
        // Kör bara i debug-läge
        #if DEBUG
            let testCases = [
                "Eventual BG 111 ≥ 100",
                "Eventual BG -123 > 456 but Min. Delta -12.34 < Exp. Delta 56.78",
                "Eventual BG 100 > 80 but Min. Delta 0.5 < Exp. Delta -1.23",
                "Eventual BG -50 > -10 but Min. Delta 0 < Exp. Delta 0.0",
                "Eventual BG 200 > 150 but Min. Delta 1.0 < Exp. Delta 2",
                "Eventual BG 112 > 100 but Min. Delta -2.00 < Exp. Delta 0",
                "Eventual BG 111 > 100 but Min. Delta -0.67 < Exp. Delta 0",
                "Eventual BG -123 &gt; 456 but Min. Delta -12.34 &lt; Exp. Delta 56.78",
                "Eventual BG 100 &gt; 80 but Min. Delta 0.5 &lt; Exp. Delta -1.23",
                "Eventual BG -50 &gt; -10 but Min. Delta 0 &lt; Exp. Delta 0.0",
                "Eventual BG 200 &gt; 150 but Min. Delta 1.0 &lt; Exp. Delta 2",
                "ISF: 54→59",
                "ISF: 66",
                "Mål: 100→110",
                "Mål: 100→110→120",
                "Dev: -38",
                "maxDelta 37 > 20% of BG 95",
                "105-80 inom mål",
                "Eventual BG 110 >= 100",
                "Eventual BG 56 < 100"
            ]

            debug(.nightscout, "🔍 Startar tester för parseReasonGlucoseValuesToMmolL")

            for (index, testString) in testCases.enumerated() {
                let result = parseReasonGlucoseValuesToMmolL(testString)
                debug(.nightscout, "Test \(index + 1): Input: '\(testString)' → Output: '\(result)'")
            }

            debug(.nightscout, "✅ Test av parseReasonGlucoseValuesToMmolL slutförd")
        #endif
    }
}
