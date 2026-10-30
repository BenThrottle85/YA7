import SwiftUI
import AppKit

struct BrowserView: View {
    @Bindable var model: BrowserModel
    @State private var sidebar = "Downloads"
    @State private var inspector = false
    @State private var sortOrder = [KeyPathComparator(\BrowserEntry.name)]
    @State private var editingPath = false
    @State private var path = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $sidebar) {
                Section(L10n.text("Favorites")) {
                    sidebarRow(L10n.text("Home"), "house", L10n.text("Home"))
                    sidebarRow(L10n.text("Desktop"), "desktopcomputer", L10n.text("Desktop"))
                    sidebarRow(L10n.text("Documents"), "doc", L10n.text("Documents"))
                    sidebarRow("Downloads", "arrow.down.circle", "Downloads")
                }
                if model.demo {
                    Section(L10n.text("Recently opened")) {
                        sidebarRow("Project Atlas.7z", "doc.zipper", "Atlas")
                        sidebarRow("Website-Assets.zip", "doc.zipper", "Assets")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 270)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YA7").font(.system(size: 12, weight: .semibold))
                        Text("Yet Another 7-Zip GUI for macOS")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }.padding(16)
            }
            .onChange(of: sidebar) { _, value in
                if model.demo {
                    if value == "Atlas" || value == "Assets" {
                        model.archiveURL = URL(fileURLWithPath: "/Examples/" + (value == "Atlas" ? "Project Atlas.7z" : "Website-Assets.zip"))
                        model.entries = BrowserEntry.archiveSamples; model.selection = []
                    } else { model.archiveURL = nil; model.entries = BrowserEntry.samples; model.selection = [] }
                } else {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    let paths = [L10n.text("Home"): "", L10n.text("Desktop"): "Desktop", L10n.text("Documents"): "Documents", "Downloads": "Downloads"]
                    model.browse(home.appendingPathComponent(paths[value] ?? ""))
                }
            }
        } detail: {
            VStack(spacing: 0) {
                pathBar
                Divider()
                if model.busy && model.dialog != .progress {
                    ProgressView(L10n.text("Reading archive…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.filtered.isEmpty {
                    ContentUnavailableView {
                        Label(model.search.isEmpty ? (model.archiveURL == nil ? L10n.text("This folder is empty") : L10n.text("This archive is empty")) : L10n.text("No search results"),
                              systemImage: model.search.isEmpty ? (model.archiveURL == nil ? "folder" : "archivebox") : "magnifyingglass")
                    } description: {
                        Text(model.search.isEmpty ? L10n.text("Open another folder or an archive.") : L10n.text("Try another search term or clear the filter."))
                    } actions: {
                        if model.search.isEmpty {
                            Button(L10n.text("Open folder…"), systemImage: "folder", action: model.chooseFolder)
                        } else {
                            Button(L10n.text("Clear search"), systemImage: "xmark.circle") { model.search = "" }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    fileTable
                }
                Divider()
                footer
            }
            .navigationTitle(model.title)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        withAnimation { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly }
                    } label: { Label(L10n.text("Sidebar"), systemImage: "sidebar.left") }
                        .help(L10n.text("Show or hide sidebar"))
                    Button(action: model.back) { Image(systemName: "chevron.left") }
                        .accessibilityLabel(L10n.text("Back"))
                        .help(L10n.text("Back")).disabled(model.history.isEmpty)
                    Button(action: model.forward) { Image(systemName: "chevron.right") }
                        .accessibilityLabel(L10n.text("Forward"))
                        .help(L10n.text("Forward")).disabled(model.forwardHistory.isEmpty)
                }
                ToolbarItem {
                    Button { model.dialog = .pack } label: { Label(L10n.text("Compress"), systemImage: "archivebox") }
                        .disabled(model.selection.isEmpty || model.archiveURL != nil || model.busy)
                }
                ToolbarItem {
                    Button { model.dialog = .extract } label: { Label(L10n.text("Extract"), systemImage: "folder.badge.plus") }
                        .disabled(!model.canExtract || model.busy)
                }
                ToolbarItem {
                    Button { model.dialog = .check } label: { Label(L10n.text("Test"), systemImage: "checkmark.shield") }
                        .disabled(!model.canExtract || model.busy)
                }
                ToolbarItem {
                    Menu {
                        Button(L10n.text("Open archive…"), systemImage: "doc.zipper", action: model.chooseArchive).keyboardShortcut("o")
                        Button(L10n.text("Open folder…"), systemImage: "folder", action: model.chooseFolder).keyboardShortcut("o", modifiers: [.command, .shift])
                        Divider()
                        Button(L10n.text("Settings…"), systemImage: "gearshape") { model.dialog = .settings }
                    } label: { Label(L10n.text("Open"), systemImage: "folder") }.help(L10n.text("Open an archive or folder"))
                }
                ToolbarItem {
                    Button { inspector.toggle() } label: { Label("Info", systemImage: "info.circle") }
                        .help(L10n.text("Show information"))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.search) { _, _ in
            model.selection.formIntersection(model.filtered.map(\.id))
        }
        .toolbar(removing: .sidebarToggle)
        .inspector(isPresented: $inspector) { InfoView(model: model).inspectorColumnWidth(min: 210, ideal: 240, max: 280) }
        .sheet(item: $model.dialog) { kind in
            switch kind {
            case .pack: PackView(model: model)
            case .extract: ExtractView(model: model)
            case .check: CheckView(model: model)
            case .progress: JobView(model: model)
            case .settings: PreferencesView()
            case .info: InfoView(model: model)
            }
        }
        .alert(L10n.text("Notice"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .background {
            Button("") { editingPath = true; path = model.location?.path ?? "" }
                .keyboardShortcut("l").hidden()
        }
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ tag: String) -> some View {
        Label { Text(title) } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
        }.tag(tag).padding(.vertical, 2)
    }

    private var pathBar: some View {
        HStack(spacing: 10) {
            Button(action: model.parent) { Label(L10n.text("Parent folder"), systemImage: "arrow.up") }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless).help(L10n.text("Parent folder"))
            if editingPath {
                TextField(L10n.text("Folder path"), text: $path).textFieldStyle(.roundedBorder)
                    .onSubmit { model.browse(URL(fileURLWithPath: path)); editingPath = false }
                    .onExitCommand { editingPath = false }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "house").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text(model.location?.lastPathComponent ?? "Downloads")
                    if let archive = model.archiveURL {
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                        Label(archive.lastPathComponent, systemImage: "doc.zipper").foregroundStyle(.primary)
                    }
                    if !model.archivePath.isEmpty {
                        Image(systemName: "chevron.right").font(.system(size: 8))
                        Text(model.archivePath)
                    }
                }.font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 8)
            }
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.text("Search here"), text: $model.search).textFieldStyle(.plain)
                    .accessibilityLabel(L10n.text("Search current folder"))
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel(L10n.text("Clear search"))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 6))
            .frame(width: 170)
        }.padding(.horizontal, 15).frame(height: 42)
    }

    private var fileTable: some View {
        Table(model.filtered.sorted(using: sortOrder), selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn(L10n.text("Name"), value: \.name) { entry in
                HStack(spacing: 9) {
                    DocumentIcon(name: entry.name, isFolder: entry.folder, size: 17)
                    Text(entry.name).lineLimit(1).truncationMode(.middle)
                }.padding(.vertical, 4)
            }.width(min: 180, ideal: 350)
            TableColumn(L10n.text("Size"), value: \.size) { entry in
                Text(entry.sizeLabel).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }.width(80)
            TableColumn(L10n.text("Kind"), value: \.kind).width(min: 85, ideal: 125)
            TableColumn(L10n.text("Modified"), value: \.modified).width(min: 125, ideal: 145)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button(L10n.text("Open"), systemImage: "arrow.up.forward.square") { if let entry = model.entries.first(where: { ids.contains($0.id) }) { model.open(entry) } }
            Divider()
            Button(L10n.text("Compress…"), systemImage: "archivebox") { model.dialog = .pack }.disabled(model.archiveURL != nil)
            Button(L10n.text("Extract…"), systemImage: "folder.badge.plus") { model.dialog = .extract }.disabled(!model.canExtract)
            Button(L10n.text("Test…"), systemImage: "checkmark.shield") { model.dialog = .check }.disabled(!model.canExtract)
            Divider()
            Button(L10n.text("Information"), systemImage: "info.circle") { inspector = true }
            if let url = model.selected.first?.url {
                Button(L10n.text("Show in Finder"), systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        } primaryAction: { ids in
            if let entry = model.entries.first(where: { ids.contains($0.id) }) { model.open(entry) }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            if model.archiveURL != nil {
                Label(L10n.text("Archive"), systemImage: "doc.zipper").foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
            }
            Text(L10n.itemCount(model.filtered.count))
            if !model.selection.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Text(L10n.format("%@ selected", model.selection.count))
                if model.selected.contains(where: { !$0.folder }) {
                    Text("·").foregroundStyle(.tertiary)
                    Text(ByteCountFormatter.string(fromByteCount: model.selected.filter { !$0.folder }.reduce(0) { $0 + $1.size }, countStyle: .file)).monospacedDigit()
                }
            }
            Spacer()
            if model.demo { Text(L10n.text("Sample data")).foregroundStyle(.tertiary) }
        }.font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).frame(height: 31)
    }
}

struct PackView: View {
    @Bindable var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Project Atlas"
    @State private var format = "7z"
    @State private var level = "5"
    @State private var password = ""
    @State private var confirmation = ""
    @State private var path = ""
    var preview = false
    var encryptedPreview = false
    var sourceLabel: String { model.demo && preview ? L10n.text("3 folders · 5 files") : L10n.selectedItemCount(model.selected.count) }
    private var invalidZIPPassword: Bool {
        format == "zip" && !password.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value <= 126 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeader(title: L10n.text("Create archive"), subtitle: sourceLabel, symbol: "archivebox")
            DialogCard {
                DialogRow(title: L10n.text("Name"), symbol: "doc") {
                    HStack(spacing: 7) {
                        TextField(L10n.text("Archive name"), text: $name).textFieldStyle(.roundedBorder).labelsHidden()
                            .accessibilityLabel(L10n.text("Archive name"))
                        Text(".\(format)").foregroundStyle(.secondary).frame(width: 65, alignment: .leading)
                    }
                }
                DialogRow(title: L10n.text("Save to"), symbol: "folder") { FolderPickerRow(path: $path) }
                Divider()
                DialogRow(title: L10n.text("Format"), symbol: "archivebox") {
                    ArchiveFormatPicker(selection: $format)
                }
                if ArchiveFormat.named(format).supportsCompression {
                DialogRow(title: L10n.text("Compression"), symbol: "slider.horizontal.3") {
                    Picker(L10n.text("Compression"), selection: $level) {
                        Text(L10n.text("Fast")).tag("1"); Text(L10n.text("Normal")).tag("5"); Text(L10n.text("Maximum")).tag("9")
                    }.labelsHidden()
                }
                }
                if ArchiveFormat.named(format).supportsPassword {
                Divider()
                DialogRow(title: L10n.text("Password"), symbol: "lock") { PasswordField(password: $password) }
                if !password.isEmpty {
                    DialogRow(title: L10n.text("Confirm"), symbol: "checkmark.shield") {
                        SecureField(L10n.text("Repeat password"), text: $confirmation).textFieldStyle(.roundedBorder).labelsHidden()
                            .accessibilityLabel(L10n.text("Confirm password"))
                    }
                }
            }
            }
            DialogNote(text: passwordNote, symbol: invalidZIPPassword || confirmationMismatch ? "exclamationmark.circle" : password.isEmpty ? "info.circle" : "lock.shield",
                       warning: invalidZIPPassword || confirmationMismatch)
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                DialogNote(text: L10n.text("Originals are preserved."), symbol: "checkmark.shield")
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: create) { Label(L10n.text("Create"), systemImage: "archivebox") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name.contains("/") || path.isEmpty || invalidZIPPassword || (!password.isEmpty && password != confirmation))
            }
        }.padding(24).frame(width: 568, height: password.isEmpty ? 450 : 490)
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: format) { password = ""; confirmation = "" }
            .onAppear {
                path = model.demo ? "/Examples/Downloads" : model.location?.path ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
                format = UserDefaults.standard.string(forKey: "defaultFormat") ?? "7z"
                level = UserDefaults.standard.string(forKey: "defaultCompression") ?? "5"
                if encryptedPreview { password = L10n.text("ExamplePassword"); confirmation = L10n.text("ExamplePassword") }
                if !model.demo, let entry = model.selected.first { name = (entry.name as NSString).deletingPathExtension }
            }
    }
    private var confirmationMismatch: Bool { !confirmation.isEmpty && password != confirmation }
    private var passwordNote: String {
        if !ArchiveFormat.named(format).supportsPassword { return L10n.text("TAR archives are created without a password.") }
        if invalidZIPPassword { return L10n.text("ZIP password: printable ASCII only. Use 7z for Unicode characters.") }
        if confirmationMismatch { return L10n.text("The passwords do not match yet.") }
        return password.isEmpty ? L10n.text("Password optional. Anyone can open the archive without a password.") : L10n.text("AES-256 encryption. Keep the password safe.")
    }
    private func create() {
        if model.demo { model.error = L10n.text("Sample data cannot be compressed. Open your own folder first."); dismiss(); return }
        let sources = model.selected.compactMap(\.url)
        let target = URL(fileURLWithPath: path).appendingPathComponent(name + "." + format)
        let engine = model.engine, selectedFormat = format, selectedLevel = level, secret = password
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            model.perform(title: L10n.text("Creating archive")) {
                try await engine.create(sources: sources, target: target, format: selectedFormat, level: selectedLevel, password: secret)
            }
        }
    }
}

struct ExtractView: View {
    @Bindable var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var folderName = "Project Atlas"
    @State private var onlySelected = false
    @State private var password = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeader(title: L10n.text("Extract archive"), subtitle: model.currentArchive?.lastPathComponent ?? "Project Atlas.7z", symbol: "folder.badge.plus")
            DialogCard {
                DialogRow(title: L10n.text("Destination folder"), symbol: "folder") { FolderPickerRow(path: $path) }
                DialogRow(title: L10n.text("Subfolder"), symbol: "folder.badge.plus") {
                    TextField(L10n.text("Folder name"), text: $folderName).textFieldStyle(.roundedBorder).labelsHidden()
                        .accessibilityLabel(L10n.text("Name of the new subfolder"))
                }
                Divider()
                DialogRow(title: L10n.text("Selection"), symbol: "checklist") {
                    Picker(L10n.text("Extract"), selection: $onlySelected) {
                        Text(L10n.text("Entire archive")).tag(false)
                        Text(L10n.text("Selected entries")).tag(true)
                    }.labelsHidden().disabled(model.archiveURL == nil || model.selection.isEmpty)
                }
                DialogRow(title: L10n.text("Password"), symbol: "lock") { PasswordField(password: $password) }
            }
            DialogNote(text: L10n.text("Extracts into a new subfolder. Existing files are preserved."), symbol: "checkmark.shield")
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                Label(folderName.isEmpty ? L10n.text("New subfolder") : folderName, systemImage: "folder.badge.plus")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: extract) { Label(L10n.text("Extract"), systemImage: "folder.badge.plus") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(path.isEmpty || folderName.isEmpty || folderName.contains("/") || [".", ".."].contains(folderName))
            }
        }.padding(24).frame(width: 568, height: 430)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                path = model.demo ? "/Examples/Downloads" : model.currentArchive?.deletingLastPathComponent().path ?? ""
                if let url = model.currentArchive { folderName = url.deletingPathExtension().lastPathComponent }
            }
    }
    private func extract() {
        if model.demo { model.error = L10n.text("Sample data cannot be extracted. Open your own archive first."); dismiss(); return }
        guard let archive = model.currentArchive else { return }
        let destination = URL(fileURLWithPath: path).appendingPathComponent(folderName)
        let entries = onlySelected ? Array(model.selection) : []
        let engine = model.engine, secret = password
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            model.perform(title: L10n.text("Extracting archive")) { try await engine.extract(archive, destination: destination, password: secret, selection: entries) }
        }
    }
}

struct CheckView: View {
    @Bindable var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    var quickAction = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeader(title: L10n.text("Test archive"), subtitle: quickAction ? L10n.text("Test integrity · sample view") : L10n.text("Test archive integrity"), symbol: "checkmark.shield")
            DialogCard {
                ArchiveSummary(name: model.currentArchive?.lastPathComponent ?? "Project Atlas.7z",
                               detail: model.demo ? L10n.text("7z archive · 18.4 MB") : L10n.text("All archive data will be tested."))
                Divider()
                DialogRow(title: L10n.text("Password"), symbol: "lock") { PasswordField(password: $password) }
            }
            DialogNote(text: L10n.text("Tests whether files are complete and undamaged. No files are extracted or modified."), symbol: "checkmark.shield")
            Divider()
            HStack {
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("Test"), systemImage: "checkmark.shield") {
                    if model.demo { dismiss(); model.error = L10n.text("Sample data. Open your own archive to test it."); return }
                    guard let archive = model.currentArchive else { return }
                    let engine = model.engine, secret = password
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        model.perform(title: L10n.text("Testing archive")) { try await engine.test(archive, password: secret) }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 510).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct JobView: View {
    @Bindable var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var details = false
    var preview = false
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            DialogHeader(title: model.result == nil ? (preview ? L10n.text("Extracting archive") : model.taskTitle) : (model.failed ? L10n.text("Operation not completed") : L10n.text("Operation completed")),
                subtitle: preview ? "Project Atlas.7z → Downloads/Project Atlas" : model.taskDetails,
                symbol: model.result == nil ? "folder.badge.plus" : (model.failed ? "exclamationmark.triangle" : "checkmark.circle"))
            if preview {
                VStack(spacing: 9) {
                    HStack { Text(L10n.text("Pictures / Cover.png")).lineLimit(1); Spacer(); Text("64 %").monospacedDigit() }
                    ProgressView(value: 0.64).accessibilityLabel(L10n.text("Progress: 64 percent"))
                    HStack { Text(L10n.text("12 of 18 files")); Spacer(); Text(L10n.text("30.8 MB of 48.2 MB")) }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if model.result == nil {
                HStack { ProgressView().controlSize(.small); Text(L10n.text("7-Zip is working…")).foregroundStyle(.secondary) }
            } else {
                ScrollView {
                    Text(model.result ?? "").font(.system(size: 12)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 180)
            }
            DisclosureGroup("Details", isExpanded: $details) {
                Text(preview ? L10n.text("7-Zip 26.05 · Extracting\nSample data for UI verification.") : model.taskDetails)
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.top, 6)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            HStack {
                Spacer()
                Button(model.result == nil ? L10n.text("Cancel") : L10n.text("Close")) {
                    if model.busy { model.cancel() }
                    dismiss()
                }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 530).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct InfoView: View {
    @Bindable var model: BrowserModel
    private var selected: [BrowserEntry] { model.selected }
    var body: some View {
        Group {
            if selected.isEmpty {
                ContentUnavailableView(L10n.text("No selection"), systemImage: "cursorarrow", description: Text(L10n.text("Select a file or folder to see its information.")))
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 10) {
                        if let first = selected.first, selected.count == 1 {
                            DocumentIcon(name: first.name, isFolder: first.folder, size: 42)
                        } else {
                            Image(systemName: "doc.on.doc").font(.system(size: 42)).foregroundStyle(.secondary).accessibilityHidden(true)
                        }
                        Text(selected.count == 1 ? selected[0].name : L10n.itemCount(selected.count))
                            .font(.headline).multilineTextAlignment(.center).textSelection(.enabled)
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        if selected.count == 1, let first = selected.first {
                            infoRow(L10n.text("Kind"), first.kind)
                            infoRow(L10n.text("Size"), first.sizeLabel)
                            infoRow(L10n.text("Modified"), first.modified)
                        } else {
                            infoRow(L10n.text("Files"), "\(selected.filter { !$0.folder }.count)")
                            infoRow(L10n.text("Folders"), "\(selected.filter(\.folder).count)")
                            infoRow(L10n.text("File size"), ByteCountFormatter.string(fromByteCount: selected.filter { !$0.folder }.reduce(0) { $0 + $1.size }, countStyle: .file))
                        }
                    }
                    if selected.count == 1, let url = selected.first?.url {
                        Divider()
                        Text(url.deletingLastPathComponent().path).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(4).truncationMode(.middle).textSelection(.enabled)
                        Button(L10n.text("Show in Finder"), systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Spacer(minLength: 0)
                }.font(.system(size: 12)).padding(20)
            }
        }.frame(minHeight: 300)
    }
    private func infoRow(_ title: String, _ value: String) -> some View {
        GridRow(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultFormat") private var format = "7z"
    @AppStorage("defaultCompression") private var level = "5"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeader(title: L10n.text("YA7 · Settings"), subtitle: "Yet Another 7-Zip GUI for macOS", symbol: "gearshape")
            DialogCard {
                DialogRow(title: L10n.text("Format"), symbol: "archivebox") {
                    ArchiveFormatPicker(selection: $format)
                }
                if ArchiveFormat.named(format).supportsCompression {
                DialogRow(title: L10n.text("Compression"), symbol: "slider.horizontal.3") {
                    Picker(L10n.text("Compression"), selection: $level) {
                        Text(L10n.text("Fast")).tag("1"); Text(L10n.text("Normal")).tag("5"); Text(L10n.text("Maximum")).tag("9")
                    }.labelsHidden()
                }
            }
            }
            DialogCard {
                Label(L10n.text("Finder Quick Actions"), systemImage: "cursorarrow.click.2")
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.text("YA7: Compress, Extract and Test — in the right-click menu under Quick Actions."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("Manage extensions…"), systemImage: "gearshape") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                }
                Text(L10n.text("Finder → Right-click → Quick Actions → Customize…"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DialogCard { SevenZipUpdateSettings() }
            Spacer(minLength: 0)
            Divider()
            HStack {
                DialogNote(text: L10n.text("7-Zip is included in the app."), symbol: "shippingbox")
                Button(L10n.text("Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 540, height: 650)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
