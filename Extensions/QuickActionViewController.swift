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
    var name = L10n.text("Archive")
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
                    let temporary = try FinderOutput.makeDirectory()
                    workingDirectory = temporary
                    destination = temporary
                }
                name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : L10n.text("Archive")
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
        phase = .running; message = L10n.text("7-Zip is working…"); cancelling = false
        task = Task {
            do {
                switch action {
                case .pack:
                    guard let destination else { return }
                    let target = destination.appendingPathComponent(name + "." + format)
                    _ = try await engine.create(sources: inputs, target: target, format: format, level: level, password: password)
                    message = L10n.format("%@ is ready.\nChoose Done to let Finder place the archive next to the selected file.", target.lastPathComponent)
                    output = target
                case .extract:
                    guard let destination else { return }
                    let target = destination.appendingPathComponent(name)
                    _ = try await engine.extract(inputs[0], destination: target, password: password, selection: [])
                    message = L10n.format("Folder “%@” is ready.\nChoose Done to let Finder place it next to the archive.", target.lastPathComponent)
                    output = target
                case .check:
                    message = try await engine.test(inputs[0], password: password)
                }
                phase = .success
                logger.notice("Finder action completed: \(self.action.rawValue, privacy: .public)")
            } catch {
                phase = .failure
                message = Task.isCancelled ? L10n.text("Operation cancelled. Original files are preserved.") : error.localizedDescription
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
                let provider = FinderOutput.provider(for: output, isDirectory: self.session.action == .extract)
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
            DialogHeader(title: session.action.title, subtitle: L10n.text("YA7 · Finder Quick Action"), symbol: session.action.symbol)
            switch session.phase {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("Loading Finder selection…")).foregroundStyle(.secondary)
                }.padding(.top, 12)
            case .configure:
                configuration
            case .running:
                DialogCard {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(session.cancelling ? L10n.text("Cancelling operation…") : L10n.text("7-Zip is working…"))
                    }
                    DialogNote(text: L10n.text("Original files are preserved."), symbol: "checkmark.shield")
                }
            case .success, .failure:
                DialogCard {
                    Label(session.phase == .success ? L10n.text("Completed successfully") : L10n.text("Operation not completed"),
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
                    DialogNote(text: session.action == .check ? L10n.text("The original is unchanged.") : L10n.text("Originals are preserved."), symbol: "checkmark.shield")
                } else { Spacer(minLength: 0) }
                if session.phase == .success || session.phase == .failure {
                    if session.phase == .failure, !session.inputs.isEmpty {
                        Button(L10n.text("Try again"), systemImage: "arrow.clockwise") { session.phase = .configure }
                    }
                    Button(L10n.text("Done")) { session.close() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.text("Cancel"), action: session.cancel).keyboardShortcut(.cancelAction).disabled(session.cancelling)
                    if session.phase == .configure {
                        Button(action: session.start) {
                            Label(session.action == .pack ? L10n.text("Create") : session.action == .extract ? L10n.text("Extract") : L10n.text("Test"), systemImage: session.action.symbol)
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
                ArchiveSummary(name: session.inputs.count == 1 ? session.inputs[0].lastPathComponent : L10n.selectedItemCount(session.inputs.count),
                    detail: session.action == .check ? L10n.text("All archive data will be tested.") : L10n.text("Selection from Finder"),
                    symbol: session.inputs.count == 1 ? (session.inputs[0].hasDirectoryPath ? "folder" : "doc.zipper") : "doc.on.doc")
                Divider()
                if session.action != .check {
                    DialogRow(title: L10n.text("Destination"), symbol: "folder") {
                        Text(L10n.text("Next to the selected file")).foregroundStyle(.secondary).font(.system(size: 12))
                    }
                    DialogRow(title: session.action == .pack ? L10n.text("Archive name") : L10n.text("Subfolder"), symbol: session.action == .pack ? "doc" : "folder.badge.plus") {
                        TextField(L10n.text("Name"), text: $session.name).labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("Name"))
                    }
                }
                if session.action == .pack {
                    DialogRow(title: L10n.text("Format"), symbol: "archivebox") {
                        ArchiveFormatPicker(selection: $session.format)
                    }
                    if ArchiveFormat.named(session.format).supportsCompression {
                    DialogRow(title: L10n.text("Compression"), symbol: "slider.horizontal.3") {
                        Picker(L10n.text("Compression"), selection: $session.level) {
                            Text(L10n.text("Fast")).tag("1"); Text(L10n.text("Normal")).tag("5"); Text(L10n.text("Maximum")).tag("9")
                        }.labelsHidden()
                    }
                }
                }
                if session.action != .pack || ArchiveFormat.named(session.format).supportsPassword {
                DialogRow(title: L10n.text("Password"), symbol: "lock") { PasswordField(password: $session.password) }
                if session.action == .pack, !session.password.isEmpty {
                    DialogRow(title: L10n.text("Confirm"), symbol: "checkmark.shield") {
                        SecureField(L10n.text("Repeat password"), text: $session.confirmation).labelsHidden().textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L10n.text("Confirm password"))
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
            return L10n.text("The passwords do not match yet.")
        }
        switch session.action {
        case .check: return L10n.text("Tests whether the archive is complete and undamaged.")
        case .extract: return L10n.text("Extracts into a new subfolder next to the archive. Finder handles name conflicts.")
        case .pack: if !ArchiveFormat.named(session.format).supportsPassword { return L10n.text("TAR archives are created without a password.") }; return session.format == "zip" ? L10n.text("ZIP password: printable ASCII characters. Use 7z for Unicode.") : L10n.text("Optional AES-256 password protection. No password is stored.")
        }
    }
}
