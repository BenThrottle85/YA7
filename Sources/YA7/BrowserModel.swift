import AppKit
import Observation

enum DialogKind: String, Identifiable {
    case pack, extract, check, progress, settings, info
    var id: String { rawValue }
}

struct BrowserSelectionSummary {
    var entries: [BrowserEntry] = []
    var fileCount = 0
    var fileSize: Int64 = 0
    var folderCount: Int { entries.count - fileCount }
}

@MainActor @Observable
final class BrowserModel {
    var entries: [BrowserEntry] = [] {
        didSet {
            updateSelectionSummary()
            updateListing(resort: true)
        }
    }
    var selection: Set<String> = [] {
        didSet { if selection != oldValue { updateSelectionSummary() } }
    }
    var search = "" {
        didSet {
            guard search != oldValue else { return }
            let visibleSelection = selected.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
            selection.formIntersection(visibleSelection.map(\.id))
            updateListing(resort: false)
        }
    }
    var sortOrder = [KeyPathComparator(\BrowserEntry.name)] {
        didSet { if sortOrder != oldValue { updateListing(resort: true) } }
    }
    private(set) var filtered: [BrowserEntry] = []
    private(set) var displayedEntries: [BrowserEntry] = []
    private(set) var selectionSummary = BrowserSelectionSummary()
    private(set) var isUpdatingListing = false
    @ObservationIgnored private var sortingTask: Task<[BrowserEntry], Never>?
    @ObservationIgnored private var listingTask: Task<Void, Never>?
    @ObservationIgnored private var listingID = UUID()
    var location: URL?
    var archiveURL: URL?
    var archivePath = ""
    var archiveEntries: [BrowserEntry] = []
    var history: [URL] = []
    var forwardHistory: [URL] = []
    var dialog: DialogKind?
    var error: String?
    var demo: Bool
    var busy = false
    private(set) var isLoading = false
    private(set) var loadingMessage = ""
    @ObservationIgnored private var navigationTask: Task<Void, Never>?
    @ObservationIgnored private var navigationID = UUID()
    @ObservationIgnored private let directoryLoader: @Sendable (URL) throws -> [BrowserEntry]
    var taskTitle = ""
    var taskDetails = ""
    var result: String?
    var failed = false
    var task: Task<Void, Never>?
    let engine = ArchiveEngine()

    init(demo: Bool, archive: Bool = false,
         directoryLoader: @escaping @Sendable (URL) throws -> [BrowserEntry] = { try BrowserModel.readDirectory($0) }) {
        self.demo = demo
        self.directoryLoader = directoryLoader
        if demo {
            entries = archive ? BrowserEntry.archiveSamples : BrowserEntry.samples
            selection = archive ? ["brief"] : ["atlas"]
            if archive { archiveURL = URL(fileURLWithPath: "/Examples/Project Atlas.7z") }
        } else {
            browse(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"), remember: false)
        }
        updateSelectionSummary()
        updateListing(resort: true)
    }

    var title: String { archiveURL?.lastPathComponent ?? location?.lastPathComponent ?? "Downloads" }
    var selected: [BrowserEntry] { selectionSummary.entries }
    var canExtract: Bool { archiveURL != nil || (selected.count == 1 && selected[0].archive) }

    private func updateSelectionSummary() {
        var summary = BrowserSelectionSummary()
        for entry in entries where selection.contains(entry.id) {
            summary.entries.append(entry)
            if !entry.folder {
                summary.fileCount += 1
                summary.fileSize += entry.size
            }
        }
        selectionSummary = summary
    }

    private func updateListing(resort: Bool) {
        listingTask?.cancel()
        listingID = UUID()
        let requestID = listingID
        let source = entries
        let query = search
        if resort {
            sortingTask?.cancel()
            let order = sortOrder
            sortingTask = Task.detached(priority: .userInitiated) { source.sorted(using: order) }
        }
        guard let sortingTask else { return }
        isUpdatingListing = true
        listingTask = Task { [weak self] in
            let sorted = await sortingTask.value
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                try Self.filterListing(source: source, sorted: sorted, query: query)
            }
            do {
                let listing = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self, requestID == self.listingID else { return }
                self.filtered = listing.filtered
                self.displayedEntries = listing.displayed
                self.isUpdatingListing = false
                self.listingTask = nil
            } catch is CancellationError {
                // A newer query, sort order or directory owns the pending result.
            } catch {
                assertionFailure("Unexpected file-list filtering error: \(error)")
            }
        }
    }

    nonisolated private static func filterListing(source: [BrowserEntry], sorted: [BrowserEntry], query: String) throws
        -> (filtered: [BrowserEntry], displayed: [BrowserEntry]) {
        try Task.checkCancellation()
        guard !query.isEmpty else { return (source, sorted) }
        var matches: [BrowserEntry] = []
        var matchingIDs: Set<String> = []
        for entry in source {
            try Task.checkCancellation()
            if entry.name.localizedStandardContains(query) {
                matches.append(entry)
                matchingIDs.insert(entry.id)
            }
        }
        let displayed = try sorted.filter { entry in
            try Task.checkCancellation()
            return matchingIDs.contains(entry.id)
        }
        return (matches, displayed)
    }

    func canExtract(_ ids: Set<String>) -> Bool {
        let targets = entries.filter { ids.contains($0.id) }
        return !targets.isEmpty && (archiveURL != nil || (targets.count == 1 && targets[0].archive))
    }

    @discardableResult
    func selectContext(_ ids: Set<String>) -> Bool {
        guard !busy, !isLoading else { return false }
        let targets = Set(entries.filter { ids.contains($0.id) }.map(\.id))
        guard !targets.isEmpty else { return false }
        selection = targets
        return true
    }
    var currentArchive: URL? { archiveURL ?? selected.first(where: \.archive)?.url }

    func browse(_ url: URL, remember: Bool = true) {
        guard !busy else { return }
        let requestID = beginNavigation(message: L10n.text("Reading folder…"))
        let loader = directoryLoader
        let worker = Task.detached(priority: .userInitiated) { try loader(url) }
        navigationTask = Task {
            do {
                let newEntries = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                guard requestID == navigationID else { return }
                if remember, let location { history.append(location); forwardHistory = [] }
                location = url; archiveURL = nil
                entries = newEntries; selection = []; search = ""; demo = false
            } catch {
                guard requestID == navigationID else { return }
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
            guard requestID == navigationID else { return }
            isLoading = false
            navigationTask = nil
        }
    }

    private func beginNavigation(message: String) -> UUID {
        navigationTask?.cancel()
        navigationID = UUID()
        loadingMessage = message
        isLoading = true
        return navigationID
    }

    nonisolated static func readDirectory(_ url: URL) throws -> [BrowserEntry] {
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey]
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let newEntries = try urls.map { file -> BrowserEntry in
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: keys)
            let folder = values.isDirectory ?? false
            let zipped = ArchiveFormat.recognizing(file.lastPathComponent) != nil
            return BrowserEntry(id: file.path, name: file.lastPathComponent,
                size: Int64(values.fileSize ?? 0), kind: values.localizedTypeDescription ?? (folder ? L10n.text("Folder") : L10n.text("File")),
                modified: values.contentModificationDate.map(formatter.string) ?? "—",
                symbol: folder ? "folder.fill" : zipped ? "doc.zipper" : "doc", folder: folder, url: file)
        }
        try Task.checkCancellation()
        return newEntries.sorted(by: Self.foldersFirst)
    }

    func back() {
        guard !busy, let url = history.popLast() else { return }
        if let location { forwardHistory.append(location) }
        browse(url, remember: false)
    }

    func forward() {
        guard !busy, let url = forwardHistory.popLast() else { return }
        if let location { history.append(location) }
        browse(url, remember: false)
    }

    func parent() {
        guard !busy else { return }
        if archiveURL != nil {
            if !demo, !archivePath.isEmpty {
                let parent = (archivePath as NSString).deletingLastPathComponent
                showArchiveLevel(parent)
                return
            }
            if demo { archiveURL = nil; entries = BrowserEntry.samples; selection = ["atlas"] }
            else if let location { browse(location, remember: false) }
        } else if let location, location.path != "/" { browse(location.deletingLastPathComponent()) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = L10n.text("Open")
        if panel.runModal() == .OK, let url = panel.url { browse(url) }
    }

    func chooseArchive() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.message = L10n.text("Choose a supported archive (e.g. ZIP, 7z, TAR, RAR, ISO or DMG).")
        if panel.runModal() == .OK, let url = panel.url { openArchive(url) }
    }

    func open(_ entry: BrowserEntry) {
        if demo {
            if entry.archive { archiveURL = URL(fileURLWithPath: "/Examples/" + entry.name); entries = BrowserEntry.archiveSamples; selection = [] }
            else if entry.folder { entries = []; selection = []; archivePath = entry.name }
            return
        }
        if archiveURL != nil {
            if entry.folder { showArchiveLevel(entry.id) }
            else { error = L10n.text("Extract this file before opening it.") }
            return
        }
        guard let url = entry.url else { return }
        if entry.folder { browse(url) }
        else if entry.archive { openArchive(url) }
        else { NSWorkspace.shared.open(url) }
    }

    func openArchive(_ url: URL) {
        guard !busy else { return }
        let requestID = beginNavigation(message: L10n.text("Reading archive…"))
        navigationTask = Task {
            do {
                let items = try await engine.list(url)
                try Task.checkCancellation()
                guard requestID == navigationID else { return }
                archiveURL = url; archiveEntries = items; demo = false
                showArchiveLevel("")
            } catch {
                guard requestID == navigationID else { return }
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
            guard requestID == navigationID else { return }
            isLoading = false
            navigationTask = nil
        }
    }

    func showArchiveLevel(_ prefix: String) {
        archivePath = prefix
        let start = prefix.isEmpty ? "" : prefix + "/"
        var children: [String: BrowserEntry] = [:]
        for entry in archiveEntries {
            let path = entry.id.replacingOccurrences(of: "\\", with: "/")
            guard path.hasPrefix(start) else { continue }
            let remainder = String(path.dropFirst(start.count))
            guard let name = remainder.split(separator: "/").first.map(String.init), !name.isEmpty else { continue }
            let id = start + name
            let folder = remainder.contains("/") || entry.folder
            if children[id] == nil || !folder {
                children[id] = BrowserEntry(id: id, name: name, size: folder ? 0 : entry.size,
                    kind: folder ? L10n.text("Folder") : entry.kind, modified: entry.modified,
                    symbol: folder ? "folder.fill" : entry.symbol, folder: folder)
            }
        }
        entries = children.values.sorted(by: Self.foldersFirst)
        selection = []; search = ""
    }

    nonisolated private static func foldersFirst(_ first: BrowserEntry, _ second: BrowserEntry) -> Bool {
        if first.folder != second.folder { return first.folder }
        return first.name.localizedStandardCompare(second.name) == .orderedAscending
    }

    func showPrototypeNote() {
        error = L10n.text("This view contains sample data. Open your own folder or archive to use the app.")
    }

    func perform(title: String, operation: @escaping () async throws -> String) {
        guard !busy, !isLoading else { return }
        busy = true; taskTitle = title; taskDetails = L10n.text("7-Zip is working…"); result = nil; failed = false; dialog = .progress
        task = Task {
            do { result = try await operation() }
            catch { failed = true; result = Task.isCancelled ? L10n.text("Operation cancelled.") : error.localizedDescription }
            busy = false
        }
    }

    func cancel() { engine.cancel(); task?.cancel(); failed = true; result = L10n.text("Cancelling operation…") }
}
