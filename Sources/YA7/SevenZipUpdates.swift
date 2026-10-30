import Foundation
import AppKit
import Observation

struct SevenZipRelease: Codable, Equatable {
    let version: String
    let url: URL

    static func components(_ text: String) -> [Int]? {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return parts.compactMap { Int($0) }
    }
    func isNewer(than bundled: String) -> Bool {
        guard var lhs = Self.components(version), var rhs = Self.components(bundled) else { return false }
        let count = max(lhs.count, rhs.count)
        lhs += Array(repeating: 0, count: count - lhs.count)
        rhs += Array(repeating: 0, count: count - rhs.count)
        return rhs.lexicographicallyPrecedes(lhs)
    }
    static func decode(_ data: Data) throws -> SevenZipRelease {
        struct Payload: Decodable { let tag_name: String; let html_url: URL; let draft: Bool; let prerelease: Bool }
        let value = try JSONDecoder().decode(Payload.self, from: data)
        guard !value.draft, !value.prerelease, components(value.tag_name) != nil,
              value.html_url.scheme == "https", value.html_url.host == "github.com",
              value.html_url.path.hasPrefix("/ip7z/7zip/releases/tag/"), value.html_url.user == nil else {
            throw ArchiveFailure.message("Die Versionsantwort von 7-Zip konnte nicht gelesen werden.")
        }
        return .init(version: value.tag_name, url: value.html_url)
    }
}

@MainActor @Observable
final class SevenZipUpdates {
    static let shared = SevenZipUpdates()
    static let week: TimeInterval = 7 * 24 * 60 * 60
    static let retry: TimeInterval = 24 * 60 * 60
    let bundledVersion: String
    var automaticEnabled: Bool { didSet { defaults.set(automaticEnabled, forKey: "sevenZipAutomaticCheck") } }
    private(set) var latest: SevenZipRelease?
    private(set) var lastSuccess: Date?
    private(set) var checking = false
    private(set) var manualError: String?
    private var lastAttempt: Date?
    private var lastFailure: String?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetch: (URLRequest) async throws -> (Data, HTTPURLResponse)
    private var inFlight: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    var availableUpdate: SevenZipRelease? { latest.flatMap { $0.isNewer(than: bundledVersion) ? $0 : nil } }

    init(defaults: UserDefaults = .standard, bundledVersion: String? = nil,
         now: @escaping () -> Date = Date.init,
         fetch: @escaping (URLRequest) async throws -> (Data, HTTPURLResponse) = { request in
             let (data, response) = try await URLSession.shared.data(for: request)
             guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
             return (data, http)
         }) {
        self.defaults = defaults; self.now = now; self.fetch = fetch
        self.bundledVersion = bundledVersion ?? Self.readBundledVersion()
        automaticEnabled = defaults.object(forKey: "sevenZipAutomaticCheck") as? Bool ?? true
        lastSuccess = defaults.object(forKey: "sevenZipLastSuccess") as? Date
        lastAttempt = defaults.object(forKey: "sevenZipLastAttempt") as? Date
        if let data = defaults.data(forKey: "sevenZipLatest"), let cached = try? JSONDecoder().decode(SevenZipRelease.self, from: data),
           SevenZipRelease.components(cached.version) != nil, cached.url.host == "github.com", cached.url.scheme == "https",
           cached.url.path.hasPrefix("/ip7z/7zip/releases/tag/") { latest = cached }
    }
    private static func readBundledVersion() -> String {
        struct Metadata: Decodable { let version: String }
        guard let resources = Bundle.main.resourceURL,
              let data = try? Data(contentsOf: resources.appendingPathComponent("Legal/Source-Provenance.json")),
              let meta = try? JSONDecoder().decode(Metadata.self, from: data),
              SevenZipRelease.components(meta.version) != nil else { return "Unbekannt" }
        return meta.version
    }
    func isDue(at date: Date) -> Bool {
        guard automaticEnabled else { return false }
        if let lastSuccess, date.timeIntervalSince(lastSuccess) < Self.week { return false }
        if let lastAttempt, lastSuccess == nil || lastAttempt > lastSuccess! {
            if date.timeIntervalSince(lastAttempt) < Self.retry { return false }
        }
        return true
    }
    func check(manual: Bool = false) async {
        if let inFlight {
            await inFlight.value
            if manual { manualError = lastFailure }
            return
        }
        guard manual || isDue(at: now()) else { return }
        checking = true; manualError = nil
        let attempt = now(); lastAttempt = attempt; defaults.set(attempt, forKey: "sevenZipLastAttempt")
        let task = Task { [self] in
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/ip7z/7zip/releases/latest")!)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("YA7/7-Zip-Version-Check", forHTTPHeaderField: "User-Agent")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await fetch(request)
                guard response.statusCode == 200, response.url?.host == "api.github.com" else { throw URLError(.badServerResponse) }
                let release = try SevenZipRelease.decode(data)
                latest = release; lastSuccess = now(); lastFailure = nil
                defaults.set(lastSuccess, forKey: "sevenZipLastSuccess")
                defaults.set(try JSONEncoder().encode(release), forKey: "sevenZipLatest")
            } catch {
                lastFailure = "Versionsprüfung nicht möglich. Bitte Internetverbindung prüfen und später erneut versuchen."
                if manual { manualError = lastFailure }
            }
            checking = false
        }
        inFlight = task
        await task.value
        inFlight = nil
    }
    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        })
    }
}
