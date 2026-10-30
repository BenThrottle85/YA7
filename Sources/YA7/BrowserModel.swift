import AppKit
import Observation

enum DialogKind: String, Identifiable {
    case pack, extract, check, progress, settings, info
    var id: String { rawValue }
}

@MainActor @Observable
final class BrowserModel {
    var entries: [BrowserEntry] = []
    var selection: Set<String> = []
    var search = ""
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
    var taskTitle = ""
    var taskDetails = ""
    var result: String?
    var failed = false
    var task: Task<Void, Never>?
    let engine = ArchiveEngine()

    init(demo: Bool, archive: Bool = false) {
        self.demo = demo
        if demo {
            entries = archive ? BrowserEntry.archiveSamples : BrowserEntry.samples
            selection = archive ? ["brief"] : ["atlas"]
            if archive { archiveURL = URL(fileURLWithPath: "/Examples/Project Atlas.7z") }
        } else {
            browse(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"), remember: false)
        }
    }

    var title: String { archiveURL?.lastPathComponent ?? location?.lastPathComponent ?? "Downloads" }
    var selected: [BrowserEntry] { entries.filter { selection.contains($0.id) } }
    var filtered: [BrowserEntry] { entries.filter { search.isEmpty || $0.name.localizedStandardContains(search) } }
    var canExtract: Bool { archiveURL != nil || (selected.count == 1 && selected[0].archive) }
    var currentArchive: URL? { archiveURL ?? selected.first(where: \.archive)?.url }

    func browse(_ url: URL, remember: Bool = true) {
        do {
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey]
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let newEntries = try urls.map { file -> BrowserEntry in
                let values = try file.resourceValues(forKeys: keys)
                let folder = values.isDirectory ?? false
                let zipped = ArchiveFormat.recognizing(file.lastPathComponent) != nil
                return BrowserEntry(id: file.path, name: file.lastPathComponent,
                    size: Int64(values.fileSize ?? 0), kind: values.localizedTypeDescription ?? (folder ? L10n.text("Folder") : L10n.text("File")),
                    modified: values.contentModificationDate.map(formatter.string) ?? "—",
                    symbol: folder ? "folder.fill" : zipped ? "doc.zipper" : "doc", folder: folder, url: file)
            }.sorted(by: Self.foldersFirst)
            if remember, let location { history.append(location); forwardHistory = [] }
            location = url; archiveURL = nil; entries = newEntries; selection = []; search = ""; demo = false
        } catch { self.error = error.localizedDescription }
    }

    func back() {
        guard let url = history.popLast() else { return }
        if let location { forwardHistory.append(location) }
        browse(url, remember: false)
    }

    func forward() {
        guard let url = forwardHistory.popLast() else { return }
        if let location { history.append(location) }
        browse(url, remember: false)
    }

    func parent() {
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
        busy = true
        Task {
            do {
                let items = try await engine.list(url)
                archiveURL = url; archiveEntries = items; demo = false
                showArchiveLevel("")
            } catch { self.error = error.localizedDescription }
            busy = false
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

    private static func foldersFirst(_ first: BrowserEntry, _ second: BrowserEntry) -> Bool {
        if first.folder != second.folder { return first.folder }
        return first.name.localizedStandardCompare(second.name) == .orderedAscending
    }

    func showPrototypeNote() {
        error = L10n.text("This view contains sample data. Open your own folder or archive to use the app.")
    }

    func perform(title: String, operation: @escaping () async throws -> String) {
        guard !busy else { return }
        busy = true; taskTitle = title; taskDetails = L10n.text("7-Zip is working…"); result = nil; failed = false; dialog = .progress
        task = Task {
            do { result = try await operation() }
            catch { failed = true; result = Task.isCancelled ? L10n.text("Operation cancelled.") : error.localizedDescription }
            busy = false
        }
    }

    func cancel() { engine.cancel(); task?.cancel(); failed = true; result = L10n.text("Cancelling operation…") }
}
