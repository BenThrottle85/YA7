import Foundation
import UniformTypeIdentifiers

enum FinderAction: String, CaseIterable {
    case pack, extract, check

    var title: String {
        switch self {
        case .pack: return L10n.text("Create archive")
        case .extract: return L10n.text("Extract archive")
        case .check: return L10n.text("Test archive")
        }
    }
    var symbol: String {
        switch self {
        case .pack: return "archivebox"
        case .extract: return "folder.badge.plus"
        case .check: return "checkmark.shield"
        }
    }
    static let archiveExtensions: Set<String> = ArchiveFormat.recognizedExtensions

    func validate(_ urls: [URL]) throws {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else {
            throw ArchiveFailure.message(L10n.text("Finder did not provide any local files."))
        }
        if self != .pack {
            guard urls.count == 1, Self.archiveExtensions.contains(urls[0].pathExtension.lowercased()),
                  (try? urls[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else {
                throw ArchiveFailure.message(L10n.text("Please select exactly one supported archive."))
            }
        }
    }
}

enum FinderInputLoader {
    static func fileURL(from provider: NSItemProvider) async throws -> URL {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let error { continuation.resume(throwing: error); return }
                    if let url = item as? URL, url.isFileURL { continuation.resume(returning: url); return }
                    if let data = item as? Data,
                       let value = String(data: data, encoding: .utf8), let url = URL(string: value), url.isFileURL {
                        continuation.resume(returning: url); return
                    }
                    continuation.resume(throwing: ArchiveFailure.message(L10n.text("The Finder file path could not be read.")))
                }
            }
        }
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .item) == true }) else {
            throw ArchiveFailure.message(L10n.text("The selected item does not contain a supported file."))
        }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, inPlace, error in
                if let error { continuation.resume(throwing: error) }
                else if let url, url.isFileURL, inPlace { continuation.resume(returning: url) }
                else { continuation.resume(throwing: ArchiveFailure.message(L10n.text("Finder could not provide the original file. Please select a local file."))) }
            }
        }
    }
}

// Finder consumes returned files after the extension has completed its request.
// Use the system replacement directory rather than an extension scratch folder.
enum FinderOutput {
    static func makeDirectory() throws -> URL {
        try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                    appropriateFor: URL(fileURLWithPath: NSHomeDirectory()), create: true)
    }

    static func provider(for output: URL, isDirectory: Bool) -> NSItemProvider {
        let provider = NSItemProvider()
        let type: UTType = isDirectory ? .folder : UTType(filenameExtension: output.pathExtension) ?? .data
        provider.suggestedName = output.lastPathComponent
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier,
                                            fileOptions: [.openInPlace], visibility: .all) { completion in
            completion(output, false, nil)
            return nil
        }
        return provider
    }
}
