import CGMBLEKit
import Combine
import Foundation
import G7SensorKit
import LibreTransmitter
import LoopKit
import LoopKitUI
import Swinject

final class PluginSource: GlucoseSource {
    private enum SensorReadingError: Error {
        case invalidG7GlucoseResponse
    }

    private let processQueue = DispatchQueue(label: "DexcomSource.processQueue")
    private let glucoseStorage: GlucoseStorage!
    private let nightscoutManager: NightscoutManager?
    private let contactImageManager: ContactImageManager?

    // Prevent spamming the same note repeatedly
    private var lastUploadedNote: (message: String, date: Date)?
    private let noteThrottleInterval: TimeInterval = 5 * 60 // 5 minuter mellan uppladdningar notes
    private var invalidGlucoseResponseNoteSent = false

    var glucoseManager: FetchGlucoseManager?

    var cgmManager: CGMManagerUI?

    var cgmHasValidSensorSession: Bool = false

    init(glucoseStorage: GlucoseStorage, glucoseManager: FetchGlucoseManager) {
        self.glucoseStorage = glucoseStorage
        self.glucoseManager = glucoseManager

        nightscoutManager = TrioApp.resolver.resolve(NightscoutManager.self)
        contactImageManager = TrioApp.resolver.resolve(ContactImageManager.self)

        cgmManager = glucoseManager.cgmManager
        cgmManager?.delegateQueue = processQueue
        cgmManager?.cgmManagerDelegate = self
    }

    /// Poll only managers that need fetching. BLE pushes are handled by the delegate.
    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        fetchIfNeeded()
            .timeout(60 * 5, scheduler: processQueue)
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
        _ manager: LoopKit.DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type: LoopKit.DeviceLogEntryType,
        message: String,
        completion _: ((Error?) -> Void)?
    ) {
        if type == .error || shouldLogCGMDeviceMessage(message) {
            debug(.deviceManager, "device Manager for \(String(describing: deviceIdentifier)) : \(message)")
        }

        // G7SensorKit only logs this failure; it does not emit a CGMReadingResult.
        // Match narrowly: other transport errors do not establish this condition.
        if manager is G7CGMManager, type == .error,
           message == "Sensor error Unable to handle glucose control response"
        {
            processQueue.async {
                _ = self.readCGMResult(readingResult: .error(SensorReadingError.invalidG7GlucoseResponse))
            }
        }

        // Trigga ENDAST när en sensorsession definitivt har övergetts/avslutats
        if message.contains("Forgetting existing sensor and starting scan for new sensor.") {
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

    private func shouldLogCGMDeviceMessage(_ message: String) -> Bool {
        // Keep decoded readings and failures, but omit routine transport hex dumps.
        if message.range(of: #"^(control|backfill|auth) [0-9a-fA-F]+$"#, options: .regularExpression) != nil {
            return false
        }

        // Match known successful authentication messages narrowly so rejected verdicts,
        // pairing/recovery messages and unexpected responses remain visible.
        if [
            "Authenticating with the saved key",
            "Already authenticated and bonded",
            "Challenge: the sensor's answer verified",
            "Challenge: verdict auth=1 bond=1"
        ].contains(message) {
            return false
        }

        if message.hasPrefix("Characteristics: authentication ") ||
            message.hasPrefix("Challenge: sending ours as display type ")
        {
            return false
        }

        if message == "Sensor connected" {
            return false
        }

        if message.contains("Sensor disconnected: suspectedEndOfSession=false") {
            return false
        }

        if message.contains("Sensor didRead G7GlucoseMessage") {
            return false
        }

        return true
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
        processQueue.async {
            switch self.readCGMResult(readingResult: readingResult) {
            case let .success(values):
                self.glucoseManager?.updateGlucoseStore(newBloodGlucose: values)
            case .failure:
                debug(.deviceManager, "CGM PLUGIN - unable to read CGM result")
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
        processQueue.async {
            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                self.cgmHasValidSensorSession = status.hasValidSensorSession
                debug(.deviceManager, "CGM status updated: hasValidSensorSession=\(status.hasValidSensorSession)")
            }
        }
    }

    // Här kan en logg som ser ut såhär skapas vid sensorfel: 2026-01-08T00:38:32+0100 [DeviceManager] PluginSource.swift - readCGMResult(readingResult:) - 197 - DEV: PLUGIN CGM - Process CGM Reading Result launched with error(G7SensorKit.AlgorithmError.unreliableState(temporarySensorIssue))
    private func readCGMResult(readingResult: CGMReadingResult) -> Result<[BloodGlucose], Error> {
        logCGMReadingResult(readingResult)

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
            var isNewGlucoseResponseFailure = false
            if let sensorError = err as? SensorReadingError, case .invalidG7GlucoseResponse = sensorError {
                // One note per outage; changing raw replies must not create more notes.
                if invalidGlucoseResponseNoteSent {
                    note = nil
                } else {
                    invalidGlucoseResponseNoteSent = true
                    isNewGlucoseResponseFailure = true
                    note = "⛔️ Dexcom G7: Kunde inte tolka sensorns glukossvar – inga nya glukosvärden från svaret"
                }
            } else if let token = stateToken {
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
                    shouldUpload = isNewGlucoseResponseFailure || (last.message != note) ||
                        (now.timeIntervalSince(last.date) > noteThrottleInterval)
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
            // Old backfill or display-only readings do not establish recovery.
            if values.contains(where: { !$0.isDisplayOnly && $0.date >= Date().addingTimeInterval(-5 * 60) }) {
                invalidGlucoseResponseNoteSent = false
            }
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

    private func logCGMReadingResult(_ readingResult: CGMReadingResult) {
        switch readingResult {
        case let .newData(values):
            guard let latest = values.first else { return }

            let latestValue = Int(latest.quantity.doubleValue(for: .milligramsPerDeciliter))
            debug(
                .deviceManager,
                "PLUGIN CGM - newData count=\(values.count) latest=\(latestValue) date=\(latest.date) trend=\(String(describing: latest.trend)) displayOnly=\(latest.isDisplayOnly)"
            )
        case .noData:
            return
        case .unreliableData:
            debug(.deviceManager, "PLUGIN CGM - unreliableData")
        case let .error(error):
            debug(.deviceManager, "PLUGIN CGM - error(\(error))")
        }
    }
}

extension PluginSource {
    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Plugin CGM source"]
    }
}
