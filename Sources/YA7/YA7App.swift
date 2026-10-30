import SwiftUI
import AppKit

enum LaunchOptions {
    static var arguments: [String] { CommandLine.arguments }
    static func value(_ key: String) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    static var rendering: Bool { value("--render") != nil }
    static var scene: String { value("--scene") ?? "main" }
    static var dark: Bool { arguments.contains("--dark") }
    static var small: Bool { arguments.contains("--small") }
    static var browser: Bool { ["main", "archive", "empty"].contains(scene) }
    static var size: CGSize {
        if browser { return small ? CGSize(width: 800, height: 520) : CGSize(width: 1100, height: 700) }
        switch scene {
        case "pack": return CGSize(width: 568, height: 450)
        case "pack-password": return CGSize(width: 568, height: 490)
        case "extract": return CGSize(width: 568, height: 430)
        case "check": return CGSize(width: 510, height: 350)
        case "progress": return CGSize(width: 530, height: 290)
        case "settings": return CGSize(width: 540, height: 650)
        default: return CGSize(width: 540, height: 430)
        }
    }
}

@main
struct YA7App: App {
    @NSApplicationDelegateAdaptor(RenderDelegate.self) private var delegate
    @State private var model: BrowserModel

    init() {
        let demo = LaunchOptions.rendering || CommandLine.arguments.contains("--demo")
        let model = BrowserModel(demo: demo, archive: LaunchOptions.scene == "archive" || LaunchOptions.scene == "extract")
        if LaunchOptions.scene == "empty" { model.entries = []; model.selection = [] }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup("YA7") {
            Group {
                switch LaunchOptions.scene {
                case "pack": PackView(model: model, preview: true)
                case "pack-password": PackView(model: model, preview: true, encryptedPreview: true)
                case "extract": ExtractView(model: model)
                case "check": CheckView(model: model, quickAction: true)
                case "progress": JobView(model: model, preview: true)
                case "settings": PreferencesView()
                default: BrowserView(model: model).frame(minWidth: 800, minHeight: 480)
                    .safeAreaInset(edge: .bottom) { SevenZipUpdateNotice() }
                }
            }
            .preferredColorScheme(LaunchOptions.rendering ? (LaunchOptions.dark ? .dark : .light) : nil)
        }
        .defaultSize(width: LaunchOptions.size.width, height: LaunchOptions.size.height)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.text("Licenses and source code…")) {
                    if let resources = Bundle.main.resourceURL {
                        NSWorkspace.shared.open(resources.appendingPathComponent("Legal", isDirectory: true))
                    }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("Open archive…"), action: model.chooseArchive).keyboardShortcut("o")
                Button(L10n.text("Open folder…"), action: model.chooseFolder).keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("Settings…")) { model.dialog = .settings }.keyboardShortcut(",")
            }
            CommandMenu(L10n.text("Archive")) {
                Button(L10n.text("Compress…")) { model.dialog = .pack }.disabled(model.selection.isEmpty || model.archiveURL != nil)
                Button(L10n.text("Extract…")) { model.dialog = .extract }.disabled(!model.canExtract)
                Button(L10n.text("Test…")) { model.dialog = .check }.disabled(!model.canExtract)
            }
        }
    }
}

final class RenderDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let testing = environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil || NSClassFromString("XCTest.XCTestCase") != nil
        if !LaunchOptions.rendering && !CommandLine.arguments.contains("--demo") && !testing && environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            SevenZipUpdates.shared.startMonitoring()
        }
        if !LaunchOptions.rendering {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.windows.forEach { $0.toolbar?.displayMode = .iconAndLabel }
            }
            return
        }
        NSApp.appearance = NSAppearance(named: LaunchOptions.dark ? .darkAqua : .aqua)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.prepare() }
    }

    private func prepare() {
        guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }) else {
            fputs("No renderable window found.\n", stderr); exit(2)
        }
        window.setContentSize(LaunchOptions.size)
        window.toolbar?.displayMode = .iconAndLabel
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if LaunchOptions.browser, let content = window.contentView {
            func table(in view: NSView) -> NSTableView? {
                if let result = view as? NSTableView { return result }
                return view.subviews.lazy.compactMap { table(in: $0) }.first
            }
            if let table = table(in: content) { window.makeFirstResponder(table) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { self.capture(window) }
    }

    private func capture(_ window: NSWindow) {
        guard let path = LaunchOptions.value("--render"),
              let view = window.contentView?.superview,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(3) }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(4) }
        do { try png.write(to: URL(fileURLWithPath: path)); print("Rendered \(LaunchOptions.scene): \(path)") }
        catch { fputs("\(error)\n", stderr); exit(5) }
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
