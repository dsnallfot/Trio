import Foundation
import SwiftDate
import System

final class SimpleLogReporter: IssueReporter {
    private let fileManager = FileManager.default
    private var isLogDirectoryReady = false
    private var activeLogStartOfDay: Date?

    private let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }()

    func setup() {}

    func setUserIdentifier(_: String?) {}

    func reportNonFatalIssue(withName _: String, attributes _: [String: String]) {}

    func reportNonFatalIssue(withError _: NSError) {}

    func log(_ category: String, _ message: String, file: String, function: String, line: UInt) {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        prepareLogFileIfNeeded(for: startOfDay)

        let logEntry = "\(dateFormatter.string(from: now)) [\(category)] \(file.file) - \(function) - \(line) - \(message)\n"
        let data = logEntry.data(using: .utf8)!
        try? data.append(fileURL: URL(fileURLWithPath: SimpleLogReporter.logFile))
    }

    private func prepareLogFileIfNeeded(for startOfDay: Date) {
        if !isLogDirectoryReady {
            try? fileManager.createDirectory(
                atPath: SimpleLogReporter.logDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            isLogDirectoryReady = true
        }

        if activeLogStartOfDay == startOfDay {
            return
        }

        guard fileManager.fileExists(atPath: SimpleLogReporter.logFile) else {
            createFile(at: startOfDay)
            activeLogStartOfDay = startOfDay
            return
        }

        if let attributes = try? fileManager.attributesOfItem(atPath: SimpleLogReporter.logFile),
           let creationDate = attributes[.creationDate] as? Date
        {
            let logFileStartOfDay = Calendar.current.startOfDay(for: creationDate)
            if logFileStartOfDay < startOfDay {
                rotateLogFile(to: startOfDay)
            } else {
                activeLogStartOfDay = logFileStartOfDay
            }
        } else {
            activeLogStartOfDay = startOfDay
        }
    }

    private func rotateLogFile(to startOfDay: Date) {
        try? fileManager.removeItem(atPath: SimpleLogReporter.logFilePrev)
        try? fileManager.moveItem(atPath: SimpleLogReporter.logFile, toPath: SimpleLogReporter.logFilePrev)
        createFile(at: startOfDay)
        activeLogStartOfDay = startOfDay
    }

    private func createFile(at date: Date) {
        fileManager.createFile(atPath: SimpleLogReporter.logFile, contents: nil, attributes: [.creationDate: date])
    }

    static var logFile: String {
        getDocumentsDirectory().appendingPathComponent("logs/log.txt").path
    }

    static var logDir: String {
        getDocumentsDirectory().appendingPathComponent("logs").path
    }

    static var logFilePrev: String {
        getDocumentsDirectory().appendingPathComponent("logs/log_prev.txt").path
    }

    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
}

private extension Data {
    func append(fileURL: URL) throws {
        let descriptor = try FileDescriptor.open(
            FilePath(fileURL.path),
            .writeOnly,
            options: [.append, .create],
            permissions: [.ownerReadWrite, .groupRead, .otherRead]
        )
        try descriptor.closeAfter { _ = try descriptor.writeAll(self) }
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}
