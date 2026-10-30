import AppKit
import SwiftUI
import Observation
import OSLog
import UniformTypeIdentifiers

@MainActor @Observable
final class QuickActionSession {
    enum Phase { case loading, configure, running, success, failure }
    let action: FinderAction
    var phase: Phase = .loading
    var inputs: [URL] = []
    var destination: URL?
    var name = "Archiv"
    var format = "7z"
    var level = "5"
    var password = ""
    var confirmation = ""
    var message = ""
    var cancelling = false
    var output: URL?
    var finish: (() -> Void)?
    var dismissRequest: (() -> Void)?
    let engine = ArchiveEngine()
    private var accesses: [URL] = []
    private var task: Task<Void, Never>?
    private var workingDirectory: URL?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "de.local.archiv", category: "FinderQuickAction")

    init(action: FinderAction) { self.action = action }

    func load(_ items: [NSExtensionItem]) {
        task = Task {
            do {
                var urls: [URL] = []
                for provider in items.flatMap({ $0.attachments ?? [] }) {
                    let url = try await FinderInputLoader.fileURL(from: provider)
                    try Task.checkCancellation()
                    if url.startAccessingSecurityScopedResource() { accesses.append(url) }
                    if !urls.contains(url) { urls.append(url) }
                }
                try action.validate(urls)
                inputs = urls
                if action != .check {
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Archiv-Schnellaktion-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
                    workingDirectory = temporary
                    destination = temporary
                }
                name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Archiv"
                format = UserDefaults.standard.string(forKey: "defaultFormat") ?? "7z"
                level = UserDefaults.standard.string(forKey: "defaultCompression") ?? "5"
                phase = .configure
                logger.notice("Finder request ready: \(self.action.rawValue, privacy: .public), inputs: \(urls.count)")
            } catch {
                message = error.localizedDescription; phase = .failure
                logger.error("Finder input loading failed")
            }
        }
    }

    var canStart: Bool {
        guard phase == .configure, !inputs.isEmpty else { return false }
        if action == .check { return true }
        guard destination != nil, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.contains("/"), !name.contains("\n"), ![".", ".."].contains(name) else { return false }
        if action == .pack {
            return (password.isEmpty || password == confirmation)
                && (format != "zip" || password.unicodeScalars.allSatisfy { (32...126).contains($0.value) })
        }
        return true
    }

    func start() {
        guard canStart else { return }
        phase = .running; message = "7-Zip arbeitet …"; cancelling = false
        task = Task {
            do {
                switch action {
                case .pack:
                    guard let destination else { return }
                    let target = destination.appendingPathComponent(name + "." + format)
                    _ = try await engine.create(sources: inputs, target: target, format: format, level: level, password: password)
                    message = "\(target.lastPathComponent) ist bereit.\nMit „Fertig“ legt Finder das Archiv neben der ausgewählten Datei ab."
                    output = target
                case .extract:
                    guard let destination else { return }
                    let target = destination.appendingPathComponent(name)
                    _ = try await engine.extract(inputs[0], destination: target, password: password, selection: [])
                    message = "Ordner „\(target.lastPathComponent)“ ist bereit.\nMit „Fertig“ legt Finder ihn neben dem Archiv ab."
                    output = target
                case .check:
                    message = try await engine.test(inputs[0], password: password)
                }
                phase = .success
                logger.notice("Finder action completed: \(self.action.rawValue, privacy: .public)")
            } catch {
                phase = .failure
                message = Task.isCancelled ? "Auftrag abgebrochen. Originaldateien bleiben erhalten." : error.localizedDescription
                logger.error("Finder action failed or cancelled: \(self.action.rawValue, privacy: .public)")
            }
            password = ""; confirmation = ""
            if cancelling { close(cancelled: true) }
        }
    }

    func cancel() {
        if phase == .running { cancelling = true; task?.cancel(); engine.cancel() }
        else { task?.cancel(); close(cancelled: true) }
    }

    func close(cancelled: Bool = false) {
        accesses.forEach { $0.stopAccessingSecurityScopedResource() }; accesses = []
        password = ""; confirmation = ""
        if cancelled || phase != .success {
            if let workingDirectory { try? FileManager.default.removeItem(at: workingDirectory) }
        }
        if cancelled { dismissRequest?() } else { finish?() }
    }
}

@objc(ArchiveQuickActionViewController)
final class QuickActionViewController: NSViewController {
    private var session: QuickActionSession!
    private var originals: [NSExtensionItem] = []
    private var loaded = false

    override func loadView() {
        let action = FinderAction(rawValue: Bundle.main.object(forInfoDictionaryKey: "ArchivAction") as? String ?? "pack") ?? .pack
        session = QuickActionSession(action: action)
        session.finish = { [weak self] in
            guard let self else { return }
            // Return every original provider unchanged: Finder must retain input files.
            var items = self.originals
            if self.session.phase == .success, let output = self.session.output {
                let provider = NSItemProvider()
                let type = output.hasDirectoryPath || self.session.action == .extract ? UTType.folder : UTType(filenameExtension: output.pathExtension) ?? .data
                provider.suggestedName = output.lastPathComponent
                provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [.openInPlace], visibility: .all) { completion in
                    completion(output, false, nil)
                    return nil
                }
                let item = NSExtensionItem()
                item.attachments = [provider]
                items.append(item)
            }
            self.extensionContext?.completeRequest(returningItems: items, completionHandler: nil)
        }
        session.dismissRequest = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
        let host = NSHostingController(rootView: QuickActionView(session: session))
        addChild(host)
        let size = QuickActionView.preferredSize(for: action)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
        preferredContentSize = size
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !loaded else { return }
        loaded = true
        originals = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        session.load(originals)
    }

    override func viewWillDisappear() {
        if session?.phase == .running { session.cancel() }
        super.viewWillDisappear()
    }
}

struct QuickActionView: View {
    @Bindable var session: QuickActionSession
    static func preferredSize(for action: FinderAction) -> NSSize {
        switch action {
        case .pack: return NSSize(width: 570, height: 490)
        case .extract: return NSSize(width: 570, height: 390)
        case .check: return NSSize(width: 570, height: 330)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DialogHeader(title: session.action.title, subtitle: "YA7 · Finder-Schnellaktion", symbol: session.action.symbol)
            switch session.phase {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Finder-Auswahl wird geladen …").foregroundStyle(.secondary)
                }.padding(.top, 12)
            case .configure:
                configuration
            case .running:
                DialogCard {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(session.cancelling ? "Auftrag wird abgebrochen …" : "7-Zip arbeitet …")
                    }
                    DialogNote(text: "Originaldateien bleiben erhalten.", symbol: "checkmark.shield")
                }
            case .success, .failure:
                DialogCard {
                    Label(session.phase == .success ? "Erfolgreich abgeschlossen" : "Auftrag nicht abgeschlossen",
                        systemImage: session.phase == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(session.phase == .success ? .green : .orange)
                        .font(.headline)
                        .accessibilityElement(children: .combine)
                    ScrollView {
                        Text(session.message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 160)
                }
            }
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                if session.phase == .configure {
                    DialogNote(text: session.action == .check ? "Original bleibt unverändert." : "Originale bleiben erhalten.", symbol: "checkmark.shield")
                } else { Spacer(minLength: 0) }
                if session.phase == .success || session.phase == .failure {
                    if session.phase == .failure, !session.inputs.isEmpty {
                        Button("Erneut versuchen", systemImage: "arrow.clockwise") { session.phase = .configure }
                    }
                    Button("Fertig") { session.close() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("Abbrechen", action: session.cancel).keyboardShortcut(.cancelAction).disabled(session.cancelling)
                    if session.phase == .configure {
                        Button(action: session.start) {
                            Label(session.action == .pack ? "Erstellen" : session.action == .extract ? "Entpacken" : "Prüfen", systemImage: session.action.symbol)
                        }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!session.canStart)
                    }
                }
            }.padding(.top, 4)
        }
        .onChange(of: session.format) { session.password = ""; session.confirmation = "" }
        .padding(24)
        .frame(width: Self.preferredSize(for: session.action).width, height: Self.preferredSize(for: session.action).height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 10) {
            DialogCard(inset: 12, spacing: 10) {
                ArchiveSummary(name: session.inputs.count == 1 ? session.inputs[0].lastPathComponent : "\(session.inputs.count) ausgewählte Objekte",
                    detail: session.action == .check ? "Alle Archivdaten werden geprüft." : "Auswahl aus Finder",
                    symbol: session.inputs.count == 1 ? (session.inputs[0].hasDirectoryPath ? "folder" : "doc.zipper") : "doc.on.doc")
                Divider()
                if session.action != .check {
                    DialogRow(title: "Ziel", symbol: "folder") {
                        Text("Neben der ausgewählten Datei").foregroundStyle(.secondary).font(.system(size: 12))
                    }
                    DialogRow(title: session.action == .pack ? "Archivname" : "Unterordner", symbol: session.action == .pack ? "doc" : "folder.badge.plus") {
                        TextField("Name", text: $session.name).labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel("Name")
                    }
                }
                if session.action == .pack {
                    DialogRow(title: "Format", symbol: "archivebox") {
                        ArchiveFormatPicker(selection: $session.format)
                    }
                    if ArchiveFormat.named(session.format).supportsCompression {
                    DialogRow(title: "Kompression", symbol: "slider.horizontal.3") {
                        Picker("Kompression", selection: $session.level) {
                            Text("Schnell").tag("1"); Text("Normal").tag("5"); Text("Maximum").tag("9")
                        }.labelsHidden()
                    }
                }
                }
                if session.action != .pack || ArchiveFormat.named(session.format).supportsPassword {
                DialogRow(title: "Passwort", symbol: "lock") { PasswordField(password: $session.password) }
                if session.action == .pack, !session.password.isEmpty {
                    DialogRow(title: "Bestätigen", symbol: "checkmark.shield") {
                        SecureField("Passwort wiederholen", text: $session.confirmation).labelsHidden().textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Passwort bestätigen")
                    }
                }
            }
            }
            DialogNote(text: helperText, symbol: session.action == .check ? "checkmark.shield" : session.action == .extract ? "folder.badge.plus" : "lock.shield",
                       warning: session.action == .pack && !session.confirmation.isEmpty && session.confirmation != session.password)
        }.padding(.top, 4)
    }
    private var helperText: String {
        if session.action == .pack, !session.confirmation.isEmpty, session.confirmation != session.password {
            return "Die Passwörter stimmen noch nicht überein."
        }
        switch session.action {
        case .check: return "Prüft, ob das Archiv vollständig und unbeschädigt ist."
        case .extract: return "Entpackt in einen neuen Unterordner neben dem Archiv. Namenskonflikte behandelt Finder."
        case .pack: if !ArchiveFormat.named(session.format).supportsPassword { return "TAR-Archive werden ohne Passwort erstellt." }; return session.format == "zip" ? "ZIP-Passwort: druckbare ASCII-Zeichen. Für Umlaute bitte 7z wählen." : "Optionaler AES-256-Passwortschutz. Kein Passwort wird gespeichert."
        }
    }
}
