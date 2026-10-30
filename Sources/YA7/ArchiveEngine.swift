import Foundation

enum ArchiveFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class ArchiveEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    var executable: URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/7zz")
        return [bundled.path, "/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    func cancel() {
        lock.lock(); let current = process; lock.unlock()
        if current?.isRunning == true { current?.terminate() }
    }

    func run(_ arguments: [String], directory: URL? = nil, password: String? = nil, outputFile: URL? = nil) async throws -> String {
        try Task.checkCancellation()
        guard let executable else { throw ArchiveFailure.message("7-Zip wurde nicht gefunden. Bitte die vollständige App verwenden.") }
        if let password, password.contains("\n") || password.contains("\r") {
            throw ArchiveFailure.message("Das Passwort darf keinen Zeilenumbruch enthalten.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = executable
                task.arguments = Array(arguments.prefix(1)) + ["-sccUTF-8", "-spd"] + arguments.dropFirst()
                task.currentDirectoryURL = directory
                var environment = ProcessInfo.processInfo.environment
                environment["LANG"] = "en_US.UTF-8"
                task.environment = environment
                let output = Pipe(), input = Pipe()
                task.standardOutput = output; task.standardError = output; task.standardInput = input
                var outputHandle: FileHandle?
                defer { try? outputHandle?.close() }
                self.setRunningProcess(task)
                do {
                    if let outputFile {
                        guard FileManager.default.createFile(atPath: outputFile.path, contents: nil) else {
                            throw ArchiveFailure.message("Zwischendatei konnte nicht erstellt werden.")
                        }
                        let handle = try FileHandle(forWritingTo: outputFile)
                        outputHandle = handle; task.standardOutput = handle
                    }
                    try task.run()
                    if let password {
                        try input.fileHandleForWriting.write(contentsOf: Data((password + "\n" + password + "\n").utf8))
                    }
                    try? input.fileHandleForWriting.close()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()
                    self.setRunningProcess(nil)
                    let text = String(decoding: data, as: UTF8.self)
                    if task.terminationStatus != 0 {
                        if text.localizedCaseInsensitiveContains("password") {
                            throw ArchiveFailure.message("Archiv konnte nicht geöffnet werden. Passwort prüfen; verschlüsselte Dateinamen werden in diesem Grundprototyp noch nicht unterstützt.")
                        }
                        throw ArchiveFailure.message("7-Zip meldet einen Fehler (\(task.terminationStatus)).\n" + String(text.suffix(1800)))
                    }
                    continuation.resume(returning: text)
                } catch {
                    self.setRunningProcess(nil)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func setRunningProcess(_ process: Process?) {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
    }

    private func records(_ archive: URL) async throws -> [[String: String]] {
        let output = try await run(["l", "-slt", "-ba", "--", archive.path])
        let normalized = output.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            var values: [String: String] = [:]
            for line in block.components(separatedBy: "\n") {
                guard let range = line.range(of: " = ") else { continue }
                values[String(line[..<range.lowerBound])] = String(line[range.upperBound...])
            }
            if values["Path"] == nil, !values.isEmpty,
               ["bz2", "xz", "zst"].contains(ArchiveFormat.recognizing(archive.lastPathComponent)?.id ?? "") {
                values["Path"] = archive.deletingPathExtension().lastPathComponent
            }
            return values["Path"] == nil ? nil : values
        }
    }

    private func listDirect(_ archive: URL) async throws -> [BrowserEntry] {
        try await records(archive).map { item in
            let name = item["Path"] ?? ""
            let folder = item["Folder"] == "+" || (item["Attributes"] ?? "").hasPrefix("D")
            return BrowserEntry(id: name, name: (name as NSString).lastPathComponent,
                size: Int64(item["Size"] ?? "0") ?? 0, kind: folder ? "Ordner" : "Datei",
                modified: String((item["Modified"] ?? "—").prefix(16)),
                symbol: folder ? "folder.fill" : "doc", folder: folder)
        }
    }

    func create(sources: [URL], target: URL, format: String, level: String, password: String) async throws -> String {
        guard ArchiveFormat.writableFormats.contains(where: { $0.id == format }) else {
            throw ArchiveFailure.message("Dieses Format kann nicht erstellt werden.")
        }
        let descriptor = ArchiveFormat.named(format)
        guard descriptor.supportsPassword || password.isEmpty else {
            throw ArchiveFailure.message("Passwortschutz ist nur für ZIP und 7z verfügbar.")
        }
        guard format != "zip" || password.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value <= 126 }) else {
            throw ArchiveFailure.message("7-Zip unterstützt bei ZIP nur Passwörter mit druckbaren ASCII-Zeichen. Für Umlaute und andere Unicode-Zeichen bitte 7z verwenden.")
        }
        guard let first = sources.first else { throw ArchiveFailure.message("Bitte mindestens eine Datei auswählen.") }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw ArchiveFailure.message("Am Ziel existiert bereits eine Datei. Bitte anderen Namen wählen.")
        }
        let parent = first.deletingLastPathComponent()
        guard sources.allSatisfy({ $0.deletingLastPathComponent() == parent }) else {
            throw ArchiveFailure.message("Bitte Dateien aus demselben Ordner auswählen.")
        }
        if let compressor = descriptor.compressor {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("YA7-Create-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: work) }
            let tar = work.appendingPathComponent("content.tar")
            let compressed = work.appendingPathComponent("content." + format)
            _ = try await create(sources: sources, target: tar, format: "tar", level: level, password: "")
            _ = try await run(["a", "-t\(compressor)", "-mx=\(level)", "-bd", "--", compressed.path, tar.lastPathComponent], directory: work)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: compressed, to: target)
            return "Archiv erfolgreich erstellt.\n\(target.path)"
        }
        let temp = target.deletingLastPathComponent().appendingPathComponent(".archiv-\(UUID().uuidString).\(format)")
        defer { try? FileManager.default.removeItem(at: temp) }
        var args = ["a", "-t\(format)", "-bd", "-snl"]
        if descriptor.supportsCompression { args.append("-mx=\(level)") }
        if !password.isEmpty { args.append("-p"); if format == "zip" { args.append("-mem=AES256") } }
        args += ["--", temp.path] + sources.map(\.lastPathComponent)
        _ = try await run(args, directory: parent, password: password.isEmpty ? nil : password)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temp, to: target)
        return "Archiv erfolgreich erstellt.\n\(target.path)"
    }

    private func extractDirect(_ archive: URL, destination: URL, password: String, selection: [String]) async throws -> String {
        let entries = try await records(archive)
        try validatePaths(entries)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ArchiveFailure.message("Zielordner existiert bereits. Bitte neuen Ordnernamen wählen; vorhandene Dateien werden nicht überschrieben.")
        }
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".archiv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temp) }
        var args = ["x", "-bd", "-y", "-o\(temp.path)"]
        args += ["--", archive.path] + selection
        _ = try await run(args, password: password.isEmpty ? nil : password)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temp, to: destination)
        return "Archiv erfolgreich entpackt.\n\(destination.path)"
    }

    private func testDirect(_ archive: URL, password: String) async throws -> String {
        let args = ["t", "-bd"]
        _ = try await run(args + ["--", archive.path], password: password.isEmpty ? nil : password)
        return "Keine Fehler gefunden.\nAlle Archivdaten wurden erfolgreich geprüft."
    }
    private func validatePaths(_ entries: [[String: String]]) throws {
        for item in entries {
            let path = item["Path"] ?? ""
            let components = path.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/")
            let attributes = item["Attributes"] ?? ""
            guard !path.hasPrefix("/"), !components.contains(".."), !path.contains(":"),
                  (item["Symbolic Link"] ?? "").isEmpty, (item["Hard Link"] ?? "").isEmpty,
                  item["Mode"]?.hasPrefix("l") != true,
                  !attributes.contains("lrwx") else {
                throw ArchiveFailure.message("Archiv enthält unsichere Pfade oder Verknüpfungen. Entpacken im Grundprototyp abgelehnt.")
            }
        }
    }

    private func withResolvedArchive<T>(_ archive: URL, password: String,
                                        operation: (URL) async throws -> T) async throws -> T {
        guard let compressor = ArchiveFormat.recognizing(archive.lastPathComponent)?.compressor else {
            return try await operation(archive)
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("YA7-TAR-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: work) }
        let inner = work.appendingPathComponent("content.tar")
        // Stream bytes into our own file: compressed-stream header names never become paths.
        _ = try await run(["x", "-t\(compressor)", "-so", "-bd", "--", archive.path],
                          password: password.isEmpty ? nil : password, outputFile: inner)
        try Task.checkCancellation()
        _ = try await run(["l", "-ttar", "-slt", "-ba", "--", inner.path])
        return try await operation(inner)
    }

    func list(_ archive: URL) async throws -> [BrowserEntry] {
        try await withResolvedArchive(archive, password: "") { try await self.listDirect($0) }
    }

    func extract(_ archive: URL, destination: URL, password: String, selection: [String]) async throws -> String {
        try await withResolvedArchive(archive, password: password) {
            try await self.extractDirect($0, destination: destination, password: password, selection: selection)
        }
    }

    func test(_ archive: URL, password: String) async throws -> String {
        try await withResolvedArchive(archive, password: password) { try await self.testDirect($0, password: password) }
    }

}
