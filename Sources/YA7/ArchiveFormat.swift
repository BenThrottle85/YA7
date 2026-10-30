import Foundation

struct ArchiveFormat: Codable, Identifiable {
    let id: String
    let title: String
    let extensions: [String]
    let writable: Bool
    let compressor: String?
    var supportsPassword: Bool { id == "7z" || id == "zip" }
    var supportsCompression: Bool { id != "tar" }
    static let all: [ArchiveFormat] = [
        .init(id: "7z", title: "7z", extensions: ["7z"], writable: true, compressor: nil),
        .init(id: "zip", title: "ZIP", extensions: ["zip"], writable: true, compressor: nil),
        .init(id: "tar", title: "TAR", extensions: ["tar"], writable: true, compressor: nil),
        .init(id: "tar.gz", title: "TAR.GZ", extensions: ["tar.gz", "tgz"], writable: true, compressor: "gzip"),
        .init(id: "tar.bz2", title: "TAR.BZ2", extensions: ["tar.bz2", "tbz", "tbz2"], writable: true, compressor: "bzip2"),
        .init(id: "tar.xz", title: "TAR.XZ", extensions: ["tar.xz", "txz"], writable: true, compressor: "xz"),
        .init(id: "tar.zst", title: "TAR.ZST", extensions: ["tar.zst", "tzst"], writable: false, compressor: "zstd"),
        .init(id: "rar", title: "RAR", extensions: ["rar"], writable: false, compressor: nil),
        .init(id: "gz", title: "GZIP", extensions: ["gz", "gzip"], writable: false, compressor: nil),
        .init(id: "bz2", title: "BZIP2", extensions: ["bz2", "bzip2"], writable: false, compressor: nil),
        .init(id: "xz", title: "XZ", extensions: ["xz"], writable: false, compressor: nil),
        .init(id: "zst", title: "Zstandard", extensions: ["zst"], writable: false, compressor: nil),
        .init(id: "cab", title: "CAB", extensions: ["cab"], writable: false, compressor: nil),
        .init(id: "iso", title: "ISO", extensions: ["iso"], writable: false, compressor: nil),
        .init(id: "dmg", title: "DMG", extensions: ["dmg"], writable: false, compressor: nil)
    ]
    static var writableFormats: [ArchiveFormat] { all.filter(\.writable) }
    static var recognizedExtensions: Set<String> { Set(all.flatMap(\.extensions).map { ($0 as NSString).pathExtension.isEmpty ? $0 : ($0 as NSString).pathExtension }) }
    static func named(_ id: String) -> ArchiveFormat { all.first { $0.id == id } ?? all[0] }
    static func recognizing(_ name: String) -> ArchiveFormat? {
        all.first { format in format.extensions.contains { name.lowercased().hasSuffix("." + $0) } }
    }
}
