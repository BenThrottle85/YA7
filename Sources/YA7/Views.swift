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
                Section("Favoriten") {
                    sidebarRow("Benutzerordner", "house", "Benutzerordner")
                    sidebarRow("Schreibtisch", "desktopcomputer", "Schreibtisch")
                    sidebarRow("Dokumente", "doc", "Dokumente")
                    sidebarRow("Downloads", "arrow.down.circle", "Downloads")
                }
                if model.demo {
                    Section("Zuletzt geöffnet") {
                        sidebarRow("Projekt Atlas.7z", "doc.zipper", "Atlas")
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
                        model.archiveURL = URL(fileURLWithPath: "/Beispiele/" + (value == "Atlas" ? "Projekt Atlas.7z" : "Website-Assets.zip"))
                        model.entries = BrowserEntry.archiveSamples; model.selection = []
                    } else { model.archiveURL = nil; model.entries = BrowserEntry.samples; model.selection = [] }
                } else {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    let paths = ["Benutzerordner": "", "Schreibtisch": "Desktop", "Dokumente": "Documents", "Downloads": "Downloads"]
                    model.browse(home.appendingPathComponent(paths[value] ?? ""))
                }
            }
        } detail: {
            VStack(spacing: 0) {
                pathBar
                Divider()
                if model.busy && model.dialog != .progress {
                    ProgressView("Archiv wird gelesen …").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.filtered.isEmpty {
                    ContentUnavailableView {
                        Label(model.search.isEmpty ? (model.archiveURL == nil ? "Dieser Ordner ist leer" : "Dieses Archiv ist leer") : "Keine Suchtreffer",
                              systemImage: model.search.isEmpty ? (model.archiveURL == nil ? "folder" : "archivebox") : "magnifyingglass")
                    } description: {
                        Text(model.search.isEmpty ? "Öffne einen anderen Ordner oder ein Archiv." : "Versuche einen anderen Suchbegriff oder lösche den Filter.")
                    } actions: {
                        if model.search.isEmpty {
                            Button("Ordner öffnen …", systemImage: "folder", action: model.chooseFolder)
                        } else {
                            Button("Suche löschen", systemImage: "xmark.circle") { model.search = "" }
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
                    } label: { Label("Seitenleiste", systemImage: "sidebar.left") }
                        .help("Seitenleiste ein- oder ausblenden")
                    Button(action: model.back) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Zurück")
                        .help("Zurück").disabled(model.history.isEmpty)
                    Button(action: model.forward) { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Vorwärts")
                        .help("Vorwärts").disabled(model.forwardHistory.isEmpty)
                }
                ToolbarItem {
                    Button { model.dialog = .pack } label: { Label("Packen", systemImage: "archivebox") }
                        .disabled(model.selection.isEmpty || model.archiveURL != nil || model.busy)
                }
                ToolbarItem {
                    Button { model.dialog = .extract } label: { Label("Entpacken", systemImage: "folder.badge.plus") }
                        .disabled(!model.canExtract || model.busy)
                }
                ToolbarItem {
                    Button { model.dialog = .check } label: { Label("Prüfen", systemImage: "checkmark.shield") }
                        .disabled(!model.canExtract || model.busy)
                }
                ToolbarItem {
                    Menu {
                        Button("Archiv öffnen …", systemImage: "doc.zipper", action: model.chooseArchive).keyboardShortcut("o")
                        Button("Ordner öffnen …", systemImage: "folder", action: model.chooseFolder).keyboardShortcut("o", modifiers: [.command, .shift])
                        Divider()
                        Button("Einstellungen …", systemImage: "gearshape") { model.dialog = .settings }
                    } label: { Label("Öffnen", systemImage: "folder") }.help("Archiv oder Ordner öffnen")
                }
                ToolbarItem {
                    Button { inspector.toggle() } label: { Label("Info", systemImage: "info.circle") }
                        .help("Informationen einblenden")
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
        .alert("Hinweis", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
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
            Button(action: model.parent) { Label("Übergeordneter Ordner", systemImage: "arrow.up") }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless).help("Übergeordneter Ordner")
            if editingPath {
                TextField("Ordnerpfad", text: $path).textFieldStyle(.roundedBorder)
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
                TextField("Hier suchen", text: $model.search).textFieldStyle(.plain)
                    .accessibilityLabel("Aktuellen Ordner durchsuchen")
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Suche löschen")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 6))
            .frame(width: 170)
        }.padding(.horizontal, 15).frame(height: 42)
    }

    private var fileTable: some View {
        Table(model.filtered.sorted(using: sortOrder), selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { entry in
                HStack(spacing: 9) {
                    DocumentIcon(name: entry.name, isFolder: entry.folder, size: 17)
                    Text(entry.name).lineLimit(1).truncationMode(.middle)
                }.padding(.vertical, 4)
            }.width(min: 180, ideal: 350)
            TableColumn("Größe", value: \.size) { entry in
                Text(entry.sizeLabel).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }.width(80)
            TableColumn("Art", value: \.kind).width(min: 85, ideal: 125)
            TableColumn("Geändert", value: \.modified).width(min: 125, ideal: 145)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Öffnen", systemImage: "arrow.up.forward.square") { if let entry = model.entries.first(where: { ids.contains($0.id) }) { model.open(entry) } }
            Divider()
            Button("Packen …", systemImage: "archivebox") { model.dialog = .pack }.disabled(model.archiveURL != nil)
            Button("Entpacken …", systemImage: "folder.badge.plus") { model.dialog = .extract }.disabled(!model.canExtract)
            Button("Prüfen …", systemImage: "checkmark.shield") { model.dialog = .check }.disabled(!model.canExtract)
            Divider()
            Button("Informationen", systemImage: "info.circle") { inspector = true }
            if let url = model.selected.first?.url {
                Button("Im Finder zeigen", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        } primaryAction: { ids in
            if let entry = model.entries.first(where: { ids.contains($0.id) }) { model.open(entry) }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            if model.archiveURL != nil {
                Label("Archiv", systemImage: "doc.zipper").foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
            }
            Text("\(model.filtered.count) Objekte")
            if !model.selection.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Text("\(model.selection.count) ausgewählt")
                if model.selected.contains(where: { !$0.folder }) {
                    Text("·").foregroundStyle(.tertiary)
                    Text(ByteCountFormatter.string(fromByteCount: model.selected.filter { !$0.folder }.reduce(0) { $0 + $1.size }, countStyle: .file)).monospacedDigit()
                }
            }
            Spacer()
            if model.demo { Text("Beispieldaten").foregroundStyle(.tertiary) }
        }.font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).frame(height: 31)
    }
}

struct PackView: View {
    @Bindable var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Projekt Atlas"
    @State private var format = "7z"
    @State private var level = "5"
    @State private var password = ""
    @State private var confirmation = ""
    @State private var path = ""
    var preview = false
    var encryptedPreview = false
    var sourceLabel: String { model.demo && preview ? "3 Ordner · 5 Dateien" : "\(model.selected.count) ausgewählte Objekte" }
    private var invalidZIPPassword: Bool {
        format == "zip" && !password.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value <= 126 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeader(title: "Archiv erstellen", subtitle: sourceLabel, symbol: "archivebox")
            DialogCard {
                DialogRow(title: "Name", symbol: "doc") {
                    HStack(spacing: 7) {
                        TextField("Archivname", text: $name).textFieldStyle(.roundedBorder).labelsHidden()
                            .accessibilityLabel("Archivname")
                        Text(".\(format)").foregroundStyle(.secondary).frame(width: 65, alignment: .leading)
                    }
                }
                DialogRow(title: "Sichern unter", symbol: "folder") { FolderPickerRow(path: $path) }
                Divider()
                DialogRow(title: "Format", symbol: "archivebox") {
                    ArchiveFormatPicker(selection: $format)
                }
                if ArchiveFormat.named(format).supportsCompression {
                DialogRow(title: "Kompression", symbol: "slider.horizontal.3") {
                    Picker("Kompression", selection: $level) {
                        Text("Schnell").tag("1"); Text("Normal").tag("5"); Text("Maximum").tag("9")
                    }.labelsHidden()
                }
                }
                if ArchiveFormat.named(format).supportsPassword {
                Divider()
                DialogRow(title: "Passwort", symbol: "lock") { PasswordField(password: $password) }
                if !password.isEmpty {
                    DialogRow(title: "Bestätigen", symbol: "checkmark.shield") {
                        SecureField("Passwort wiederholen", text: $confirmation).textFieldStyle(.roundedBorder).labelsHidden()
                            .accessibilityLabel("Passwort bestätigen")
                    }
                }
            }
            }
            DialogNote(text: passwordNote, symbol: invalidZIPPassword || confirmationMismatch ? "exclamationmark.circle" : password.isEmpty ? "info.circle" : "lock.shield",
                       warning: invalidZIPPassword || confirmationMismatch)
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                DialogNote(text: "Originale bleiben erhalten.", symbol: "checkmark.shield")
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: create) { Label("Erstellen", systemImage: "archivebox") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name.contains("/") || path.isEmpty || invalidZIPPassword || (!password.isEmpty && password != confirmation))
            }
        }.padding(24).frame(width: 568, height: password.isEmpty ? 450 : 490)
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: format) { password = ""; confirmation = "" }
            .onAppear {
                path = model.demo ? "/Beispiele/Downloads" : model.location?.path ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
                format = UserDefaults.standard.string(forKey: "defaultFormat") ?? "7z"
                level = UserDefaults.standard.string(forKey: "defaultCompression") ?? "5"
                if encryptedPreview { password = "Beispielpasswort"; confirmation = "Beispielpasswort" }
                if !model.demo, let entry = model.selected.first { name = (entry.name as NSString).deletingPathExtension }
            }
    }
    private var confirmationMismatch: Bool { !confirmation.isEmpty && password != confirmation }
    private var passwordNote: String {
        if !ArchiveFormat.named(format).supportsPassword { return "TAR-Archive werden ohne Passwort erstellt." }
        if invalidZIPPassword { return "ZIP-Passwort: nur ASCII-Zeichen. Für Umlaute bitte 7z wählen." }
        if confirmationMismatch { return "Die Passwörter stimmen noch nicht überein." }
        return password.isEmpty ? "Passwort optional. Ohne Passwort kann jeder das Archiv öffnen." : "AES-256-Verschlüsselung. Passwort sicher aufbewahren."
    }
    private func create() {
        if model.demo { model.error = "Beispieldaten können nicht gepackt werden. Bitte zuerst eigenen Ordner öffnen."; dismiss(); return }
        let sources = model.selected.compactMap(\.url)
        let target = URL(fileURLWithPath: path).appendingPathComponent(name + "." + format)
        let engine = model.engine, selectedFormat = format, selectedLevel = level, secret = password
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            model.perform(title: "Archiv wird erstellt") {
                try await engine.create(sources: sources, target: target, format: selectedFormat, level: selectedLevel, password: secret)
            }
        }
    }
}

struct ExtractView: View {
    @Bindable var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var folderName = "Projekt Atlas"
    @State private var onlySelected = false
    @State private var password = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeader(title: "Archiv entpacken", subtitle: model.currentArchive?.lastPathComponent ?? "Projekt Atlas.7z", symbol: "folder.badge.plus")
            DialogCard {
                DialogRow(title: "Zielordner", symbol: "folder") { FolderPickerRow(path: $path) }
                DialogRow(title: "Unterordner", symbol: "folder.badge.plus") {
                    TextField("Ordnername", text: $folderName).textFieldStyle(.roundedBorder).labelsHidden()
                        .accessibilityLabel("Name des neuen Unterordners")
                }
                Divider()
                DialogRow(title: "Auswahl", symbol: "checklist") {
                    Picker("Entpacken", selection: $onlySelected) {
                        Text("Gesamtes Archiv").tag(false)
                        Text("Ausgewählte Einträge").tag(true)
                    }.labelsHidden().disabled(model.archiveURL == nil || model.selection.isEmpty)
                }
                DialogRow(title: "Passwort", symbol: "lock") { PasswordField(password: $password) }
            }
            DialogNote(text: "Entpackt in einen neuen Unterordner. Vorhandene Dateien bleiben erhalten.", symbol: "checkmark.shield")
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                Label(folderName.isEmpty ? "Neuer Unterordner" : folderName, systemImage: "folder.badge.plus")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: extract) { Label("Entpacken", systemImage: "folder.badge.plus") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(path.isEmpty || folderName.isEmpty || folderName.contains("/") || [".", ".."].contains(folderName))
            }
        }.padding(24).frame(width: 568, height: 430)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                path = model.demo ? "/Beispiele/Downloads" : model.currentArchive?.deletingLastPathComponent().path ?? ""
                if let url = model.currentArchive { folderName = url.deletingPathExtension().lastPathComponent }
            }
    }
    private func extract() {
        if model.demo { model.error = "Beispieldaten können nicht entpackt werden. Bitte zuerst ein eigenes Archiv öffnen."; dismiss(); return }
        guard let archive = model.currentArchive else { return }
        let destination = URL(fileURLWithPath: path).appendingPathComponent(folderName)
        let entries = onlySelected ? Array(model.selection) : []
        let engine = model.engine, secret = password
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            model.perform(title: "Archiv wird entpackt") { try await engine.extract(archive, destination: destination, password: secret, selection: entries) }
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
            DialogHeader(title: "Archiv prüfen", subtitle: quickAction ? "Integrität prüfen · Ansicht mit Beispieldaten" : "Integrität des Archivs überprüfen", symbol: "checkmark.shield")
            DialogCard {
                ArchiveSummary(name: model.currentArchive?.lastPathComponent ?? "Projekt Atlas.7z",
                               detail: model.demo ? "7z-Archiv · 18,4 MB" : "Alle Archivdaten werden geprüft.")
                Divider()
                DialogRow(title: "Passwort", symbol: "lock") { PasswordField(password: $password) }
            }
            DialogNote(text: "Prüft, ob Dateien vollständig und unbeschädigt sind. Es werden keine Dateien entpackt oder verändert.", symbol: "checkmark.shield")
            Divider()
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Prüfen", systemImage: "checkmark.shield") {
                    if model.demo { dismiss(); model.error = "Beispieldaten. Zum Prüfen bitte eigenes Archiv öffnen."; return }
                    guard let archive = model.currentArchive else { return }
                    let engine = model.engine, secret = password
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        model.perform(title: "Archiv wird geprüft") { try await engine.test(archive, password: secret) }
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
            DialogHeader(title: model.result == nil ? (preview ? "Archiv wird entpackt" : model.taskTitle) : (model.failed ? "Auftrag nicht abgeschlossen" : "Auftrag abgeschlossen"),
                subtitle: preview ? "Projekt Atlas.7z → Downloads/Projekt Atlas" : model.taskDetails,
                symbol: model.result == nil ? "folder.badge.plus" : (model.failed ? "exclamationmark.triangle" : "checkmark.circle"))
            if preview {
                VStack(spacing: 9) {
                    HStack { Text("Bilder / Titelbild.png").lineLimit(1); Spacer(); Text("64 %").monospacedDigit() }
                    ProgressView(value: 0.64).accessibilityLabel("Fortschritt: 64 Prozent")
                    HStack { Text("12 von 18 Dateien"); Spacer(); Text("30,8 MB von 48,2 MB") }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if model.result == nil {
                HStack { ProgressView().controlSize(.small); Text("7-Zip arbeitet …").foregroundStyle(.secondary) }
            } else {
                ScrollView {
                    Text(model.result ?? "").font(.system(size: 12)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 180)
            }
            DisclosureGroup("Details", isExpanded: $details) {
                Text(preview ? "7-Zip 26.05 · Entpacken\nBeispieldaten für die Oberflächenprüfung." : model.taskDetails)
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.top, 6)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            HStack {
                Spacer()
                Button(model.result == nil ? "Abbrechen" : "Schließen") {
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
                ContentUnavailableView("Keine Auswahl", systemImage: "cursorarrow", description: Text("Wähle eine Datei oder einen Ordner, um Informationen anzuzeigen."))
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 10) {
                        if let first = selected.first, selected.count == 1 {
                            DocumentIcon(name: first.name, isFolder: first.folder, size: 42)
                        } else {
                            Image(systemName: "doc.on.doc").font(.system(size: 42)).foregroundStyle(.secondary).accessibilityHidden(true)
                        }
                        Text(selected.count == 1 ? selected[0].name : "\(selected.count) Objekte")
                            .font(.headline).multilineTextAlignment(.center).textSelection(.enabled)
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        if selected.count == 1, let first = selected.first {
                            infoRow("Art", first.kind)
                            infoRow("Größe", first.sizeLabel)
                            infoRow("Geändert", first.modified)
                        } else {
                            infoRow("Dateien", "\(selected.filter { !$0.folder }.count)")
                            infoRow("Ordner", "\(selected.filter(\.folder).count)")
                            infoRow("Dateigröße", ByteCountFormatter.string(fromByteCount: selected.filter { !$0.folder }.reduce(0) { $0 + $1.size }, countStyle: .file))
                        }
                    }
                    if selected.count == 1, let url = selected.first?.url {
                        Divider()
                        Text(url.deletingLastPathComponent().path).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(4).truncationMode(.middle).textSelection(.enabled)
                        Button("Im Finder zeigen", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
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
            DialogHeader(title: "YA7 · Einstellungen", subtitle: "Yet Another 7-Zip GUI for macOS", symbol: "gearshape")
            DialogCard {
                DialogRow(title: "Format", symbol: "archivebox") {
                    ArchiveFormatPicker(selection: $format)
                }
                if ArchiveFormat.named(format).supportsCompression {
                DialogRow(title: "Kompression", symbol: "slider.horizontal.3") {
                    Picker("Kompression", selection: $level) {
                        Text("Schnell").tag("1"); Text("Normal").tag("5"); Text("Maximum").tag("9")
                    }.labelsHidden()
                }
            }
            }
            DialogCard {
                Label("Finder-Schnellaktionen", systemImage: "cursorarrow.click.2")
                    .font(.system(size: 13, weight: .semibold))
                Text("YA7: Packen, Entpacken und Prüfen — direkt im Rechtsklick-Menü unter „Schnellaktionen“.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Erweiterungen verwalten …", systemImage: "gearshape") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                }
                Text("Finder → Rechtsklick → Schnellaktionen → Anpassen …")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DialogCard { SevenZipUpdateSettings() }
            Spacer(minLength: 0)
            Divider()
            HStack {
                DialogNote(text: "7-Zip ist in der App enthalten.", symbol: "shippingbox")
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 540, height: 650)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
