import Foundation

struct BrowserEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let size: Int64
    let kind: String
    let modified: String
    let symbol: String
    let folder: Bool
    var url: URL? = nil
    var sizeLabel: String { folder ? "—" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    var archive: Bool { ArchiveFormat.recognizing(name) != nil }

    static let samples: [BrowserEntry] = [
        .init(id: "briefing", name: "Briefing", size: 0, kind: L10n.text("Folder"), modified: L10n.text("Today, 14:32"), symbol: "folder.fill", folder: true),
        .init(id: "design", name: "Design", size: 0, kind: L10n.text("Folder"), modified: L10n.text("Today, 14:28"), symbol: "folder.fill", folder: true),
        .init(id: "fotos", name: "Photos", size: 0, kind: L10n.text("Folder"), modified: L10n.text("Yesterday, 16:05"), symbol: "folder.fill", folder: true),
        .init(id: "atlas", name: "Project Atlas.7z", size: 18_400_000, kind: L10n.text("7-Zip archive"), modified: L10n.text("Today, 14:35"), symbol: "doc.zipper", folder: false),
        .init(id: "assets", name: "Website-Assets.zip", size: 8_200_000, kind: L10n.text("ZIP archive"), modified: L10n.text("Today, 11:12"), symbol: "doc.zipper", folder: false),
        .init(id: "pdf", name: "Project overview.pdf", size: 2_400_000, kind: L10n.text("PDF document"), modified: L10n.text("Yesterday, 17:40"), symbol: "doc.richtext", folder: false),
        .init(id: "readme", name: "Read me.txt", size: 2_100, kind: L10n.text("Text document"), modified: "24.10.2026, 09:16", symbol: "doc.text", folder: false),
        .init(id: "image", name: "Preview.png", size: 3_600_000, kind: L10n.text("PNG image"), modified: "23.10.2026, 10:02", symbol: "photo", folder: false)
    ]

    static let archiveSamples: [BrowserEntry] = [
        .init(id: "docs", name: L10n.text("Documents"), size: 0, kind: L10n.text("Folder"), modified: L10n.text("Today, 14:32"), symbol: "folder.fill", folder: true),
        .init(id: "pictures", name: L10n.text("Pictures"), size: 0, kind: L10n.text("Folder"), modified: L10n.text("Today, 14:28"), symbol: "folder.fill", folder: true),
        .init(id: "font", name: L10n.text("Fonts"), size: 0, kind: L10n.text("Folder"), modified: L10n.text("Yesterday, 16:05"), symbol: "folder.fill", folder: true),
        .init(id: "brief", name: "Briefing.pdf", size: 2_400_000, kind: L10n.text("PDF document"), modified: L10n.text("Today, 14:32"), symbol: "doc.richtext", folder: false),
        .init(id: "cover", name: "Cover.png", size: 4_800_000, kind: L10n.text("PNG image"), modified: L10n.text("Today, 14:28"), symbol: "photo", folder: false),
        .init(id: "notes", name: "Notes.txt", size: 3_200, kind: L10n.text("Text document"), modified: L10n.text("Yesterday, 17:40"), symbol: "doc.text", folder: false)
    ]
}

