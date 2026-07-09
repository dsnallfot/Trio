import CGMBLEKit
import Combine
import Foundation
import G7SensorKit
import LibreTransmitter
import LoopKit
import LoopKitUI
import Swinject

final class PluginSource: GlucoseSource {
    private let processQueue = DispatchQueue(label: "DexcomSource.processQueue")
    private let glucoseStorage: GlucoseStorage!
    private let nightscoutManager: NightscoutManager?
    private let contactImageManager: ContactImageManager?

    // Prevent spamming the same note repeatedly
    private var lastUploadedNote: (message: String, date: Date)?
    private let noteThrottleInterval: TimeInterval = 10 * 60

    var glucoseManager: FetchGlucoseManager?

    var cgmManager: CGMManagerUI?

    var cgmHasValidSensorSession: Bool = false

    private var promise: Future<[BloodGlucose], Error>.Promise?

    // --- Diagnostics: measure "push w/o awaiting fetch" frequency ---
    private var directStoredCount: Int = 0 // hadPromise == false
    private var timerFetchStoredCount: Int = 0 // hadPromise == true

    private var lastCounterLogAt: Date = .distantPast
    private let counterLogInterval: TimeInterval = 10 * 60 // logga summering max var 10:e minut

    init(glucoseStorage: GlucoseStorage, glucoseManager: FetchGlucoseManager) {
        self.glucoseStorage = glucoseStorage
        self.glucoseManager = glucoseManager

        nightscoutManager = TrioApp.resolver.resolve(NightscoutManager.self)
        contactImageManager = TrioApp.resolver.resolve(ContactImageManager.self)

        cgmManager = glucoseManager.cgmManager
        cgmManager?.delegateQueue = processQueue
        cgmManager?.cgmManagerDelegate = self
    }

    /// Function that fetches blood glucose data
    /// This function combines two data fetching mechanisms (`callBLEFetch` and `fetchIfNeeded`) into a single publisher.
    /// It returns the first non-empty result from either of the sources within a 5-minute timeout period.
    /// If no valid data is fetched within the timeout, it returns an empty array.
    ///
    /// - Parameter timer: An optional `DispatchTimer` (not used in the function but can be used to trigger fetch logic).
    /// - Returns: An `AnyPublisher` that emits an array of `BloodGlucose` values or an empty array if an error occurs or the timeout is reached.
    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Publishers.Merge(
            callBLEFetch(),
            fetchIfNeeded()
        )
        .filter { !$0.isEmpty }
        .first()
        .timeout(60 * 5, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func callBLEFetch() -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60 * 5, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            guard let self = self else { return }
            self.processQueue.async {
                guard let cgmManager = self.cgmManager else { return }
                cgmManager.fetchNewDataIfNeeded { result in
                    promise(self.readCGMResult(readingResult: result))
                }
            }
        }
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    private func refreshContactImagesIfBGStaleStateChanged() {
        Task { @MainActor [weak self] in
            await self?.contactImageManager?.refreshContactImagesIfStaleStateChanged()
        }
    }

    private func setContactImagesForceStaleBG(_ forceStaleBG: Bool) {
        Task { @MainActor [weak self] in
            await self?.contactImageManager?.setForceStaleBG(forceStaleBG)
        }
    }

    deinit {
        // dexcomManager.transmitter.stopScanning()
    }
}

extension PluginSource: CGMManagerDelegate {
    func deviceManager(
        _: LoopKit.DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type _: LoopKit.DeviceLogEntryType,
        message: String,
        completion _: ((Error?) -> Void)?
    ) {
        debug(.deviceManager, "device Manager for \(String(describing: deviceIdentifier)) : \(message)")

        if message.contains("Sensor disconnected: suspectedEndOfSession=true") {
            let sensorName = deviceIdentifier ?? "okänd sensor"
            let note = "⛔️ Sensorsession \(sensorName) avslutades i Trio"
            let now = Date()
            let shouldUpload: Bool

            if let last = lastUploadedNote {
                shouldUpload = (last.message != note) || (now.timeIntervalSince(last.date) > noteThrottleInterval)
            } else {
                shouldUpload = true
            }

            if shouldUpload {
                lastUploadedNote = (note, now)
                Task { [weak self] in
                    await self?.nightscoutManager?.uploadNoteTreatment(note: note)
                }
            }
        }
    }

    func issueAlert(_: LoopKit.Alert) {}

    func retractAlert(identifier _: LoopKit.Alert.Identifier) {}

    func doesIssuedAlertExist(identifier _: LoopKit.Alert.Identifier, completion _: @escaping (Result<Bool, Error>) -> Void) {}

    func lookupAllUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[LoopKit.PersistedAlert], Error>) -> Void
    ) {}

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[LoopKit.PersistedAlert], Error>) -> Void
    ) {}

    func recordRetractedAlert(_: LoopKit.Alert, at _: Date) {}

    func cgmManagerWantsDeletion(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, " CGM Manager with identifier \(manager.pluginIdentifier) wants deletion")
        // TODO:
        glucoseManager?.cgmGlucoseSourceType = .none
    }

    func cgmManager(_: CGMManager, hasNew readingResult: CGMReadingResult) {
        // Convert the reading into Trio's BloodGlucose model (or an error)
        let result = readCGMResult(readingResult: readingResult)

        // If a fetch() call is currently awaiting a value, fulfill it.
        // (We clear the stored promise to avoid accidentally completing it more than once.)
        let hadPromise = (promise != nil)
        let currentPromise = promise
        promise = nil
        currentPromise?(result)

        // IMPORTANT:
        // CGM managers can push readings at arbitrary times. If no fetch() is currently awaiting
        // (i.e. `promise` is nil), the reading would otherwise be dropped, leading to missed
        // "New glucose found" and missed loop cycles.
        // To avoid that, we also store the glucose immediately on every successful push.
        if case let .success(values) = result, !values.isEmpty {
            // ✅ Store immediately so pushes aren't lost
            glucoseManager?.updateGlucoseStore(newBloodGlucose: values)

            // 1) Extra “försäkring”: logga explicit när Direct return done sker med hadPromise=false,
            // så du kan mäta exakt hur ofta det händer och om det korrelerar med andra loggar.
            if hadPromise {
                debug(.deviceManager, "CGM PLUGIN - Direct return done (hadPromise=true) ✅ (timer/fetch was awaiting)")
            } else {
                warning(
                    .deviceManager,
                    "CGM PLUGIN - Direct return done (hadPromise=false) 🟡 Stored immediately (no fetch awaiting)"
                )
            }

            // 2) Superlätt räknare: antal directStored / antal timerFetchStored
            if hadPromise {
                timerFetchStoredCount += 1
            } else {
                directStoredCount += 1
            }

            // Periodisk summering (för att inte spamma loggen)
            let now = Date()
            if now.timeIntervalSince(lastCounterLogAt) > counterLogInterval {
                debug(
                    .deviceManager,
                    "CGM PLUGIN - Counters: directStored=\(directStoredCount), timerFetchStored=\(timerFetchStoredCount)"
                )
                lastCounterLogAt = now
            }
        }
    }

    func cgmManager(_: LoopKit.CGMManager, hasNew events: [LoopKit.PersistedCgmEvent]) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        // TODO: Events in APS ?
        // currently only display in log the date of the event
        events.forEach { event in
            debug(.deviceManager, "events from CGM at \(event.date)")

            if event.type == .sensorStart {
                self.glucoseManager?.removeCalibrations()
            }
        }
    }

    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return glucoseStorage.lastGlucoseDate()
    }

    func cgmManagerDidUpdateState(_ cgmManager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))

        guard let fetchGlucoseManager = glucoseManager else {
            debug(
                .deviceManager,
                "Could not gracefully unwrap FetchGlucoseManager upon observing LoopKit's cgmManagerDidUpdateState"
            )
            return
        }
        // Adjust app-specific NS Upload setting value when CGM setting is changed
        fetchGlucoseManager.settingsManager.settings.uploadGlucose = cgmManager.shouldSyncToRemoteService

        fetchGlucoseManager.updateGlucoseSource(
            cgmGlucoseSourceType: fetchGlucoseManager.settingsManager.settings.cgm,
            cgmGlucosePluginId: fetchGlucoseManager.settingsManager.settings.cgmPluginIdentifier,
            newManager: cgmManager as? CGMManagerUI
        )
    }

    func credentialStoragePrefix(for _: CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        UUID().uuidString
    }

    func cgmManager(_: CGMManager, didUpdate status: CGMManagerStatus) {
        debug(.deviceManager, "CGM status updated: hasValidSensorSession=\(status.hasValidSensorSession)")
        processQueue.async {
            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                self.cgmHasValidSensorSession = status.hasValidSensorSession
            }
        }
    }

    // Här kan en logg som ser ut såhär skapas vid sensorfel: 2026-01-08T00:38:32+0100 [DeviceManager] PluginSource.swift - readCGMResult(readingResult:) - 197 - DEV: PLUGIN CGM - Process CGM Reading Result launched with error(G7SensorKit.AlgorithmError.unreliableState(temporarySensorIssue))
    private func readCGMResult(readingResult: CGMReadingResult) -> Result<[BloodGlucose], Error> {
        let debugMessage = "PLUGIN CGM - Process CGM Reading Result launched with \(readingResult)"
        debug(.deviceManager, debugMessage)

        // If this is a Dexcom G7 error, optionally upload a user-friendly note to Nightscout.
        // NOTE: G7SensorKit.AlgorithmError is internal (not public), so we can't type-cast to it here.
        // Instead we parse the string representation, which (per logs) looks like:
        // error(G7SensorKit.AlgorithmError.unreliableState(temporarySensorIssue))
        if case let .error(err) = readingResult {
            // Only attempt this mapping when the active manager is a G7 manager
            guard cgmManager is G7CGMManager else { return .failure(err) }

            let errString = String(describing: err)

            // Extract the token inside unreliableState(...)
            let stateToken: String? = {
                guard let range = errString.range(of: "unreliableState(") else { return nil }
                let after = errString[range.upperBound...]
                // token ends at the first ')'
                guard let end = after.firstIndex(of: ")") else { return nil }
                return String(after[..<end])
            }()

            let note: String?
            if let token = stateToken {
                switch token {
                case "temporarySensorIssue":
                    note = "⚠️ Dexcom G7: Tillfälligt sensorfel!"
                case "ok":
                    note = nil
                case "stopped":
                    note = "⛔️ Dexcom G7: Sensor stoppades"
                case "warmup":
                    note = "⚠️ Dexcom G7: Sensor värms upp"
                case "expired":
                    note = "⛔️ Dexcom G7: Sensor löpt ut!"
                case "sensorFailed":
                    note = "⛔️ Dexcom G7: Kritiskt fel - sensorbyte krävs!"
                default:
                    note = "⚠️ Dexcom G7: Okänt fel"
                }
            } else {
                // Not an unreliableState(...) string, but still a G7 error
                note = "⚠️ Dexcom G7: Okänt fel"
            }

            if let note = note {
                let now = Date()
                let shouldUpload: Bool
                if let last = lastUploadedNote {
                    shouldUpload = (last.message != note) || (now.timeIntervalSince(last.date) > noteThrottleInterval)
                } else {
                    shouldUpload = true
                }

                if shouldUpload {
                    lastUploadedNote = (note, now)
                    Task { [weak self] in
                        await self?.nightscoutManager?.uploadNoteTreatment(note: note)
                    }
                }
            }
        }

        if glucoseManager?.glucoseSource == nil {
            debug(
                .deviceManager,
                "No glucose source available."
            )
        }

        switch readingResult {
        case let .newData(values):
            if values.isNotEmpty {
                setContactImagesForceStaleBG(false)
            }

            var sensorActivatedAt: Date?
            var sensorStartDate: Date?
            var sensorTransmitterID: String?

            /// SAGE
            if let cgmTransmitterManager = cgmManager as? LibreTransmitterManagerV3 {
                let sensorInfo = cgmTransmitterManager.sensorInfoObservable
                sensorActivatedAt = sensorInfo.activatedAt
                sensorStartDate = sensorInfo.activatedAt
                sensorTransmitterID = sensorInfo.sensorSerial
            } else if let cgmTransmitterManager = cgmManager as? G5CGMManager {
                let latestReading = cgmTransmitterManager.latestReading
                sensorActivatedAt = latestReading?.activationDate
                sensorStartDate = latestReading?.sessionStartDate
                sensorTransmitterID = latestReading?.transmitterID
            } else if let cgmTransmitterManager = cgmManager as? G6CGMManager {
                let latestReading = cgmTransmitterManager.latestReading
                sensorActivatedAt = latestReading?.activationDate
                sensorStartDate = latestReading?.sessionStartDate
                sensorTransmitterID = latestReading?.transmitterID
            } else if let cgmTransmitterManager = cgmManager as? G7CGMManager {
                sensorActivatedAt = cgmTransmitterManager.sensorActivatedAt
                sensorStartDate = cgmTransmitterManager.sensorActivatedAt
                sensorTransmitterID = cgmTransmitterManager.sensorName
            }

            let bloodGlucose = values.compactMap { newGlucoseSample -> BloodGlucose? in
                let quantity = newGlucoseSample.quantity

                let value = Int(quantity.doubleValue(for: .milligramsPerDeciliter))
                return BloodGlucose(
                    _id: UUID().uuidString,
                    sgv: value,
                    direction: .init(trendType: newGlucoseSample.trend),
                    date: Decimal(Int(newGlucoseSample.date.timeIntervalSince1970 * 1000)),
                    dateString: newGlucoseSample.date,
                    unfiltered: Decimal(value),
                    filtered: nil,
                    noise: nil,
                    glucose: value,
                    type: "sgv",
                    activationDate: sensorActivatedAt,
                    sessionStartDate: sensorStartDate,
                    transmitterID: sensorTransmitterID
                )
            }
            return .success(bloodGlucose)
        case .unreliableData:
            setContactImagesForceStaleBG(true)
            refreshContactImagesIfBGStaleStateChanged()
            return .failure(GlucoseDataError.unreliableData)

        case .noData:
            setContactImagesForceStaleBG(true)
            refreshContactImagesIfBGStaleStateChanged()
            return .failure(GlucoseDataError.noData)

        case let .error(error):
            setContactImagesForceStaleBG(true)
            refreshContactImagesIfBGStaleStateChanged()
            return .failure(error)
        }
    }
}

extension PluginSource {
    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Plugin CGM source"]
    }
}
