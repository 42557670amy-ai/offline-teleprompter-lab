import Foundation
import UIKit
import Combine

final class Diagnostics: ObservableObject {
    struct Event: Codable {
        let seconds: Double
        let type: String
        let data: [String: String]
    }
    @Published private(set) var eventCount = 0
    private var events: [Event] = []
    private let start = ProcessInfo.processInfo.systemUptime
    let sessionID = UUID().uuidString
    private var handle: FileHandle?
    private var logDirectory: URL?
    private var storageError: String?

    init() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ProbeLogs")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logDirectory = directory
            let url = directory.appendingPathComponent("\(sessionID).jsonl")
            try Data().write(to: url)
            handle = try FileHandle(forWritingTo: url)
        } catch { storageError = error.localizedDescription }
    }

    // All calls are marshalled onto the main queue by their owners.
    func add(_ type: String, _ data: [String: String] = [:]) {
        let event = Event(seconds: ProcessInfo.processInfo.systemUptime - start, type: type, data: data)
        events.append(event)
        if events.count > 6000 { events.removeFirst(events.count - 6000) }
        eventCount += 1
        do {
            var data = try JSONEncoder().encode(event)
            data.append(10)
            try handle?.write(contentsOf: data)
            if type == "heartbeat" || type == "interruption_began" || type == "user_stop" {
                try handle?.synchronize()
            }
        } catch { storageError = error.localizedDescription }
    }
    func export() throws -> URL {
        struct Report: Codable {
            let schema: Int
            let sessionID: String
            let systemVersion: String
            let model: String
            let build: String
            let events: [Event]
            let priorSessionLogs: [String: String]
            let storageError: String?
        }
        var prior: [String: String] = [:]
        if let directory = logDirectory {
            let urls = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "jsonl" && $0.deletingPathExtension().lastPathComponent != sessionID }
                .sorted { a, b in
                    let first = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let second = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return first > second
                }
            for url in urls.prefix(3) {
                prior[url.lastPathComponent] = try String(contentsOf: url, encoding: .utf8)
            }
        }
        let report = Report(schema: 1, sessionID: sessionID,
            systemVersion: UIDevice.current.systemVersion, model: UIDevice.current.model,
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown", events: events,
            priorSessionLogs: prior, storageError: storageError)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("teleprompter-\(sessionID).json")
        try encoder.encode(report).write(to: url, options: .atomic)
        return url
    }
    deinit { try? handle?.close() }
}
