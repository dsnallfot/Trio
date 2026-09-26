import Combine
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import SwiftDate
import Swinject
import UIKit

protocol FetchGlucoseManager: SourceInfoProvider {
    func updateGlucoseStore(newBloodGlucose: [BloodGlucose])
    func refreshCGM()
    func updateGlucoseSource(cgmGlucoseSourceType: CGMType, cgmGlucosePluginId: String, newManager: CGMManagerUI?)
    func deleteGlucoseSource()
    func removeCalibrations()
    var glucoseSource: GlucoseSource? { get }
    var cgmManager: CGMManagerUI? { get }
    var cgmGlucoseSourceType: CGMType { get set }
    var cgmGlucosePluginId: String { get }
    var settingsManager: SettingsManager! { get }
    var shouldSyncToRemoteService: Bool { get }
}

extension FetchGlucoseManager {
    func updateGlucoseSource(cgmGlucoseSourceType: CGMType, cgmGlucosePluginId: String) {
        updateGlucoseSource(cgmGlucoseSourceType: cgmGlucoseSourceType, cgmGlucosePluginId: cgmGlucosePluginId, newManager: nil)
    }
}

final class BaseFetchGlucoseManager: FetchGlucoseManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseManager.processQueue")

    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var tidepoolService: TidepoolManager!
    @Injected() var apsManager: APSManager!
    @Injected() var settingsManager: SettingsManager!
    @Injected() var healthKitManager: HealthKitManager!
    @Injected() var deviceDataManager: DeviceDataManager!
    @Injected() var pluginCGMManager: PluginManager!
    @Injected() var calibrationService: CalibrationService!
    @Injected() var contactImageManager: ContactImageManager!
    private func refreshContactImagesIfBGStaleStateChanged() {
        Task { @MainActor [weak self] in
            await self?.contactImageManager.refreshContactImagesIfStaleStateChanged()
        }
    }

    private var lifetime = Lifetime()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)
    var cgmGlucoseSourceType: CGMType = .none
    var cgmGlucosePluginId: String = ""
    var cgmManager: CGMManagerUI? {
        didSet {
            rawCGMManager = cgmManager?.rawValue
            UserDefaults.standard.clearLegacyCGMManagerRawValue()
        }
    }

    @PersistedProperty(key: "CGMManagerState") var rawCGMManager: CGMManager.RawValue?

    private lazy var simulatorSource = GlucoseSimulatorSource()

    private let context = CoreDataStack.shared.newTaskContext()

    var shouldSyncToRemoteService: Bool {
        guard let cgmManager = cgmManager else {
            return true
        }
        return cgmManager.shouldSyncToRemoteService
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        // init at the start of the app
        cgmGlucoseSourceType = settingsManager.settings.cgm
        cgmGlucosePluginId = settingsManager.settings.cgmPluginIdentifier
        // load cgmManager
        updateGlucoseSource(
            cgmGlucoseSourceType: settingsManager.settings.cgm,
            cgmGlucosePluginId: settingsManager.settings.cgmPluginIdentifier
        )
        subscribe()
    }

    var glucoseSource: GlucoseSource?

    func removeCalibrations() {
        calibrationService.removeAllCalibrations()
    }

    func deleteGlucoseSource() {
        cgmManager = nil
        updateGlucoseSource(
            cgmGlucoseSourceType: CGMType.none,
            cgmGlucosePluginId: ""
        )
    }

    func saveConfigManager() {
        guard let cgmM = cgmManager else {
            return
        }
        // save the config in rawCGMManager
        rawCGMManager = cgmM.rawValue

        // sync with upload glucose
        settingsManager.settings.uploadGlucose = cgmM.shouldSyncToRemoteService
    }

    private func updateManagerUnits(_ manager: CGMManagerUI?) {
        let units = settingsManager.settings.units
        let managerName = cgmManager.map { "\(type(of: $0))" } ?? "nil"
        let loopkitUnits: HKUnit = units == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter
        print("manager: \(managerName) is changing units to: \(loopkitUnits.description) ")
        manager?.unitDidChange(to: loopkitUnits)
    }

    func updateGlucoseSource(cgmGlucoseSourceType: CGMType, cgmGlucosePluginId: String, newManager: CGMManagerUI?) {
        let oldCGMGlucoseSourceType = self.cgmGlucoseSourceType
        let oldCGMGlucosePluginId = self.cgmGlucosePluginId
        let oldManagerName = cgmManager.map { "\(type(of: $0))" } ?? "nil"

        // if changed, remove all calibrations
        if oldCGMGlucoseSourceType != cgmGlucoseSourceType || oldCGMGlucosePluginId != cgmGlucosePluginId {
            removeCalibrations()
            cgmManager = nil
            glucoseSource = nil
        }

        self.cgmGlucoseSourceType = cgmGlucoseSourceType
        self.cgmGlucosePluginId = cgmGlucosePluginId

        // if not plugin, manager is not changed and stay with the "old" value if the user come back to previous cgmtype
        // if plugin, if the same pluginID, no change required because the manager is available
        // if plugin, if not the same pluginID, need to reset the cgmManager
        // if plugin and newManager provides, update cgmManager
        if let manager = newManager
        {
            cgmManager = manager
            removeCalibrations()
        } else if self.cgmGlucoseSourceType == .plugin, cgmManager == nil, let rawCGMManager = rawCGMManager {
            cgmManager = cgmManagerFromRawValue(rawCGMManager)
            updateManagerUnits(cgmManager)

        } else {
            saveConfigManager()
        }

        let newManagerName = cgmManager.map { "\(type(of: $0))" } ?? "nil"
        if oldCGMGlucoseSourceType != cgmGlucoseSourceType ||
            oldCGMGlucosePluginId != cgmGlucosePluginId ||
            oldManagerName != newManagerName
        {
            debug(
                .apsManager,
                "CGM source updated: type=\(cgmGlucoseSourceType) plugin=\(cgmGlucosePluginId) manager=\(newManagerName)"
            )
        }

        if glucoseSource == nil {
            switch self.cgmGlucoseSourceType {
            case .none:
                glucoseSource = nil
            case .xdrip:
                glucoseSource = AppGroupSource(from: "xDrip", cgmType: .xdrip)
            case .nightscout:
                glucoseSource = nightscoutManager
            case .simulator:
                glucoseSource = simulatorSource
            case .enlite:
                glucoseSource = deviceDataManager
            case .plugin:
                glucoseSource = PluginSource(glucoseStorage: glucoseStorage, glucoseManager: self)
            }
        }

        // Only an active plugin CGM with its own BLE connection can wake the app; otherwise the pump must heartbeat
        let cgmProvidesHeartbeat = cgmGlucoseSourceType == .plugin && (cgmManager?.providesBLEHeartbeat ?? false)
        deviceDataManager.updateCGMHeartbeatCapability(providesBLEHeartbeat: cgmProvidesHeartbeat)
    }

    /// Upload cgmManager from raw value
    func cgmManagerFromRawValue(_ rawValue: [String: Any]) -> CGMManagerUI? {
        guard let rawState = rawValue["state"] as? CGMManager.RawStateValue,
              let Manager = pluginCGMManager.getCGMManagerTypeByIdentifier(cgmGlucosePluginId)
        else {
            return nil
        }
        return Manager.init(rawState: rawState)
    }

    /// Serialize BLE pushes with polled readings, including separately delivered backfill batches.
    public func updateGlucoseStore(newBloodGlucose: [BloodGlucose]) {
        processQueue.async {
            self.glucoseStoreAndHeartDecision(syncDate: self.glucoseStorage.syncDate(), glucose: newBloodGlucose)
        }
    }

    /// function to try to force the refresh of the CGM - generally provide by the pump heartbeat
    public func refreshCGM() {
        debug(.deviceManager, "refreshCGM by pump")

        Publishers.CombineLatest(
            Just(glucoseStorage.syncDate()),
            glucoseSource?.fetchIfNeeded()
                ?? Empty<[BloodGlucose], Never>().eraseToAnyPublisher()
        )
        .eraseToAnyPublisher()
        .receive(on: processQueue)
        .sink { syncDate, glucose in
            debug(.nightscout, "refreshCGM FETCHGLUCOSE : SyncDate is \(syncDate)")
            self.glucoseStoreAndHeartDecision(syncDate: self.glucoseStorage.syncDate(), glucose: glucose)
        }
        .store(in: &lifetime)
    }

    private func fetchGlucose() -> [GlucoseStored]? {
        CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 6
        ) as? [GlucoseStored]
    }

    private func processGlucose() -> [BloodGlucose] {
        context.performAndWait {
            guard let results = fetchGlucose() else { return [] }
            return results.map { result in
                BloodGlucose(
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose),
                    type: "sgv"
                )
            }
        }
    }

    private func glucoseStoreAndHeartDecision(syncDate: Date, glucose: [BloodGlucose]) {
        // calibration add if required only for sensor
        let newGlucose = overcalibrate(entries: glucose)

        var filteredByDate: [BloodGlucose] = []
        var filtered: [BloodGlucose] = []

        // start background time extension
        var backGroundFetchBGTaskID: UIBackgroundTaskIdentifier?
        backGroundFetchBGTaskID = UIApplication.shared.beginBackgroundTask(withName: "save BG starting") {
            guard let bg = backGroundFetchBGTaskID else { return }
            BackgroundTaskDiagnostics.shared.record(.expiration, id: bg, name: "glucose", reason: "time-limit")
            UIApplication.shared.endBackgroundTask(bg)
            BackgroundTaskDiagnostics.shared.record(.end, id: bg, name: "glucose", reason: "expiration")
            backGroundFetchBGTaskID = .invalid
        }
        if let id = backGroundFetchBGTaskID {
            BackgroundTaskDiagnostics.shared.record(.start, id: id, name: "glucose")
        }

        guard newGlucose.isNotEmpty else {
            refreshContactImagesIfBGStaleStateChanged()

            if let backgroundTask = backGroundFetchBGTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                BackgroundTaskDiagnostics.shared.record(.end, id: backgroundTask, name: "glucose", reason: "empty")
                backGroundFetchBGTaskID = .invalid
            }
            return
        }

        let backfill = newGlucose.filter { $0.dateString <= syncDate }
        if !backfill.isEmpty {
            glucoseStorage.backfillGlucose(backfill)
        }

        filteredByDate = newGlucose.filter { $0.dateString > syncDate }
        filtered = glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)

        guard filtered.isNotEmpty else {
            refreshContactImagesIfBGStaleStateChanged()

            // end of the Background tasks
            if let backgroundTask = backGroundFetchBGTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                BackgroundTaskDiagnostics.shared.record(.end, id: backgroundTask, name: "glucose", reason: "filtered-empty")
                backGroundFetchBGTaskID = .invalid
            }
            return
        }
        debug(.deviceManager, "New glucose found")

        // filter the data if it is the case
        if settingsManager.settings.smoothGlucose {
            // limited to 30 min of old glucose data
            let oldGlucoseValues = processGlucose()

            var smoothedValues = oldGlucoseValues + filtered
            // smooth with 3 repeats
            for _ in 1 ... 3 {
                smoothedValues.smoothSavitzkyGolayQuaDratic(withFilterWidth: 3)
            }
            // find the new values only
            filtered = smoothedValues.filter { $0.dateString > syncDate }
        }

        let storedGlucose = glucoseStorage.storeGlucose(filtered)

        // Push the fresh reading schedule so the pump can align its BLE heartbeat
        if !storedGlucose.isEmpty {
            deviceDataManager.updatePumpBLEHeartbeat(
                lastCGMReadingDate: storedGlucose.map(\.dateString).max(),
                expectedCGMReadingInterval: cgmManager?.expectedGlucoseSampleInterval
            )
            deviceDataManager.heartbeat(date: Date())
        }

        // End of the Background tasks
        if let backgroundTask = backGroundFetchBGTaskID {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            BackgroundTaskDiagnostics.shared.record(.end, id: backgroundTask, name: "glucose", reason: "processed")
            backGroundFetchBGTaskID = .invalid
        }
    }

    /// The function used to start the timer sync - Function of the variable defined in config
    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { [weak self] _ -> AnyPublisher<[BloodGlucose], Never> in
                guard let self = self else {
                    return Empty().eraseToAnyPublisher()
                }

                // Minska loggning // debug(.nightscout, "FetchGlucoseManager timer heartbeat")
                if let glucoseSource = self.glucoseSource {
                    return glucoseSource.fetch(self.timer).eraseToAnyPublisher()
                } else {
                    return Empty().eraseToAnyPublisher()
                }
            }
            .receive(on: processQueue)
            .sink { [weak self] glucose in
                guard let self = self else { return }

                // Minska loggning // debug(.nightscout, "FetchGlucoseManager callback sensor")
                self.glucoseStoreAndHeartDecision(
                    syncDate: self.glucoseStorage.syncDate(),
                    glucose: glucose
                )
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()
    }

    func sourceInfo() -> [String: Any]? {
        glucoseSource?.sourceInfo()
    }

    private func overcalibrate(entries: [BloodGlucose]) -> [BloodGlucose] {
        // overcalibrate
        var overcalibration: ((Int) -> (Double))?

        if let cal = calibrationService {
            overcalibration = cal.calibrate
        }

        if let overcalibration = overcalibration {
            return entries.map { entry in
                var entry = entry
                entry.glucose = Int(overcalibration(entry.glucose!))
                entry.sgv = Int(overcalibration(entry.sgv!))
                return entry
            }
        } else {
            return entries
        }
    }
}

extension CGMManager {
    typealias RawValue = [String: Any]

    var rawValue: [String: Any] {
        [
            "managerIdentifier": pluginIdentifier,
            "state": rawState
        ]
    }
}

// Observes loop, glucose and upload task IDs; it never starts or ends UIKit tasks.
// All mutable bookkeeping is protected by lock.
final class BackgroundTaskDiagnostics: @unchecked Sendable {
    static let shared = BackgroundTaskDiagnostics()

    enum Event: String {
        case start
        case end
        case expiration
    }

    private let lock = NSLock()
    private var openTasks: [UIBackgroundTaskIdentifier: TimeInterval] = [:]
    private var sequence: UInt64 = 0

    func record(_ event: Event, id: UIBackgroundTaskIdentifier, name: String, reason: String = "-") {
        lock.lock()
        sequence += 1
        let serial = sequence
        let now = ProcessInfo.processInfo.systemUptime
        let started = openTasks[id]
        let valid = id != .invalid
        let status: String
        switch event {
        case .start:
            status = !valid ? "invalid-id" : (started == nil ? "ok" : "already-open")
            if valid, started == nil { openTasks[id] = now }
        case .end:
            status = !valid ? "invalid-id" : (started == nil ? "untracked-id" : "ok")
            openTasks.removeValue(forKey: id)
        case .expiration:
            status = !valid ? "invalid-id" : (started == nil ? "untracked-id" : "ok")
        }
        let duration = started.map { String(format: "%.3f", now - $0) } ?? (event == .start && valid ? "0.000" : "unknown")
        let openCount = openTasks.count
        let oldest = openTasks.values.min().map { String(format: "%.3f", now - $0) } ?? "0.000"
        lock.unlock()

        guard DiagnosticLogging.isEnabled else { return }
        debug(
            .deviceManager,
            "BGTask pid=\(ProcessInfo.processInfo.processIdentifier) seq=\(serial) name=\(name) id=\(id.rawValue) " +
                "event=\(event.rawValue) reason=\(reason) durationSec=\(duration) trackedOpen=\(openCount) " +
                "oldestOpenSec=\(oldest) status=\(status)"
        )
    }
}
