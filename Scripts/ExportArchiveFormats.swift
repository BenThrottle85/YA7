import Foundation
import UniformTypeIdentifiers

@main struct ExportArchiveFormats {
    static func main() throws {
        let rows: [[String: Any]] = ArchiveFormat.all.map { format in
            let extensions = Array(Set(format.extensions.map { ($0 as NSString).pathExtension.isEmpty ? $0 : ($0 as NSString).pathExtension })).sorted()
            let types = extensions.map { ext -> String in
                if let type = UTType(filenameExtension: ext), !type.isDynamic { return type.identifier }
                return "de.local.archiv.format." + ext
            }
            return ["id": format.id, "title": format.compressor?.uppercased() ?? format.title, "extensions": extensions, "types": types]
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
