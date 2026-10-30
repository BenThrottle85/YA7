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
        .init(id: "briefing", name: "Briefing", size: 0, kind: "Ordner", modified: "Heute, 14:32", symbol: "folder.fill", folder: true),
        .init(id: "design", name: "Design", size: 0, kind: "Ordner", modified: "Heute, 14:28", symbol: "folder.fill", folder: true),
        .init(id: "fotos", name: "Fotos", size: 0, kind: "Ordner", modified: "Gestern, 16:05", symbol: "folder.fill", folder: true),
        .init(id: "atlas", name: "Projekt Atlas.7z", size: 18_400_000, kind: "7-Zip-Archiv", modified: "Heute, 14:35", symbol: "doc.zipper", folder: false),
        .init(id: "assets", name: "Website-Assets.zip", size: 8_200_000, kind: "ZIP-Archiv", modified: "Heute, 11:12", symbol: "doc.zipper", folder: false),
        .init(id: "pdf", name: "Projektübersicht.pdf", size: 2_400_000, kind: "PDF-Dokument", modified: "Gestern, 17:40", symbol: "doc.richtext", folder: false),
        .init(id: "readme", name: "Lies mich.txt", size: 2_100, kind: "Textdokument", modified: "24.10.2026, 09:16", symbol: "doc.text", folder: false),
        .init(id: "image", name: "Vorschau.png", size: 3_600_000, kind: "PNG-Bild", modified: "23.10.2026, 10:02", symbol: "photo", folder: false)
    ]

    static let archiveSamples: [BrowserEntry] = [
        .init(id: "docs", name: "Dokumente", size: 0, kind: "Ordner", modified: "Heute, 14:32", symbol: "folder.fill", folder: true),
        .init(id: "pictures", name: "Bilder", size: 0, kind: "Ordner", modified: "Heute, 14:28", symbol: "folder.fill", folder: true),
        .init(id: "font", name: "Schriften", size: 0, kind: "Ordner", modified: "Gestern, 16:05", symbol: "folder.fill", folder: true),
        .init(id: "brief", name: "Briefing.pdf", size: 2_400_000, kind: "PDF-Dokument", modified: "Heute, 14:32", symbol: "doc.richtext", folder: false),
        .init(id: "cover", name: "Titelbild.png", size: 4_800_000, kind: "PNG-Bild", modified: "Heute, 14:28", symbol: "photo", folder: false),
        .init(id: "notes", name: "Notizen.txt", size: 3_200, kind: "Textdokument", modified: "Gestern, 17:40", symbol: "doc.text", folder: false)
    ]
}

