import XCTest
@testable import YA7

final class ArchiveEngineTests: XCTestCase {
    func testFinderSelectionValidation() throws {
        let (root, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("Test.zip")
        try Data().write(to: archive)
        XCTAssertNoThrow(try FinderAction.pack.validate([file, archive]))
        XCTAssertNoThrow(try FinderAction.extract.validate([archive]))
        XCTAssertNoThrow(try FinderAction.check.validate([archive]))
        XCTAssertThrowsError(try FinderAction.pack.validate([]))
        XCTAssertThrowsError(try FinderAction.check.validate([file]))
        XCTAssertThrowsError(try FinderAction.extract.validate([archive, archive]))
        XCTAssertThrowsError(try FinderAction.pack.validate([URL(string: "https://example.com/test.zip")!]))
    }

    func testFinderProviderRetainsOriginalFileURL() async throws {
        let (root, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = NSItemProvider(item: file as NSURL, typeIdentifier: "public.file-url")
        let received = try await FinderInputLoader.fileURL(from: provider)
        XCTAssertEqual(received.standardizedFileURL, file.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testFinderOutputSurvivesHandoffForArchiveAndFolder() async throws {
        let (root, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try FinderOutput.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(directory.path.contains("TemporaryItems"))
        let archive = directory.appendingPathComponent("Finder result.zip")
        _ = try await ArchiveEngine().create(sources: [file], target: archive, format: "zip", level: "5", password: "")
        let folder = directory.appendingPathComponent("Extracted", isDirectory: true)
        _ = try await ArchiveEngine().extract(archive, destination: folder, password: "", selection: [])
        for (output, type, isDirectory) in [(archive, "public.zip-archive", false), (folder, "public.folder", true)] {
            let provider = FinderOutput.provider(for: output, isDirectory: isDirectory)
            XCTAssertEqual(provider.suggestedName, output.lastPathComponent)
            let received: URL = try await withCheckedThrowingContinuation { continuation in
                provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, _, error in
                    do {
                        if let error { throw error }
                        let url = try XCTUnwrap(url)
                        // Simulate Finder consuming the output after request completion.
                        let copy = root.appendingPathComponent(output.lastPathComponent)
                        try FileManager.default.copyItem(at: url, to: copy)
                        continuation.resume(returning: copy)
                    } catch { continuation.resume(throwing: error) }
                }
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: received.path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YA7Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Grüße & [Entwurf].txt")
        try Data("Native Archive — Grüße aus macOS!\n".utf8).write(to: file)
        return (root, file)
    }

    func testZIPAnd7zRoundTripsIncludingPasswords() async throws {
        let (root, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ArchiveEngine()
        for format in ["7z", "zip"] {
            for secret in ["", format == "7z" ? "Sicher ü & $ [2026]" : "Sicher & $ [2026]"] {
                let suffix = secret.isEmpty ? "offen" : "geschützt"
                let target = root.appendingPathComponent("Test-\(suffix).\(format)")
                _ = try await engine.create(sources: [file], target: target, format: format, level: "5", password: secret)
                let entries = try await engine.list(target)
                XCTAssertEqual(entries.map(\.name), [file.lastPathComponent])
                _ = try await engine.test(target, password: secret)
                let destination = root.appendingPathComponent("Ausgabe-\(format)-\(suffix)")
                _ = try await engine.extract(target, destination: destination, password: secret, selection: [])
                XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(file.lastPathComponent)), try Data(contentsOf: file))
                XCTAssertEqual(try Data(contentsOf: file), Data("Native Archive — Grüße aus macOS!\n".utf8))
            }
        }
    }

    func testExistingArchiveAndExtractionFolderArePreserved() async throws {
        let (root, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ArchiveEngine()
        let target = root.appendingPathComponent("Existiert.7z")
        _ = try await engine.create(sources: [file], target: target, format: "7z", level: "1", password: "")
        let original = try Data(contentsOf: target)
        do {
            _ = try await engine.create(sources: [file], target: target, format: "7z", level: "1", password: "")
            XCTFail("Existing archive must not be overwritten")
        } catch { XCTAssertEqual(try Data(contentsOf: target), original) }
        let destination = root.appendingPathComponent("Bestehend")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            _ = try await engine.extract(target, destination: destination, password: "", selection: [])
            XCTFail("Existing extraction folder must not be overwritten")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path)) }
    }

    func testWrongPasswordAndCorruptArchiveFail() async throws {
        let (root, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ArchiveEngine()
        let target = root.appendingPathComponent("Geheim.7z")
        _ = try await engine.create(sources: [file], target: target, format: "7z", level: "1", password: "richtig")
        do { _ = try await engine.test(target, password: "falsch"); XCTFail("Wrong password must fail") } catch { }
        let broken = root.appendingPathComponent("Defekt.zip")
        try Data("Kein Archiv".utf8).write(to: broken)
        do { _ = try await engine.list(broken); XCTFail("Corrupt archive must fail") } catch { }
    }

    func testSelectedFilesOnly() async throws {
        let (root, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = root.appendingPathComponent("Nicht ausgewählt.txt")
        try Data("Andere Datei".utf8).write(to: other)
        let engine = ArchiveEngine()
        let archive = root.appendingPathComponent("Auswahl.zip")
        _ = try await engine.create(sources: [file, other], target: archive, format: "zip", level: "1", password: "")
        let destination = root.appendingPathComponent("Auswahl")
        _ = try await engine.extract(archive, destination: destination, password: "", selection: [file.lastPathComponent])
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent(file.lastPathComponent).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent(other.lastPathComponent).path))
    }

    func testUnsafeArchivePathIsRejected() async throws {
        let (root, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let malicious = root.appendingPathComponent("Pfadausbruch.zip")
        let python = Process()
        python.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        python.arguments = ["-c", "import sys,zipfile; z=zipfile.ZipFile(sys.argv[1],'w'); z.writestr('../ausbruch.txt','nicht schreiben'); z.close()", malicious.path]
        try python.run(); python.waitUntilExit(); XCTAssertEqual(python.terminationStatus, 0)
        let destination = root.appendingPathComponent("Ausgabe")
        do {
            _ = try await ArchiveEngine().extract(malicious, destination: destination, password: "", selection: [])
            XCTFail("Unsafe path must fail before extraction")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ausbruch.txt").path))
        }
    }

    @MainActor func testArchiveFolderNavigation() {
        let model = BrowserModel(demo: true)
        model.demo = false
        model.archiveEntries = [
            .init(id: "Ordner/Unterordner/a.txt", name: "a.txt", size: 4, kind: "Datei", modified: "—", symbol: "doc", folder: false),
            .init(id: "b.txt", name: "b.txt", size: 8, kind: "Datei", modified: "—", symbol: "doc", folder: false)
        ]
        model.showArchiveLevel("")
        XCTAssertEqual(model.entries.map(\.name), ["Ordner", "b.txt"])
        model.showArchiveLevel("Ordner")
        XCTAssertEqual(model.entries.map(\.name), ["Unterordner"])
        model.showArchiveLevel("Ordner/Unterordner")
        XCTAssertEqual(model.entries.map(\.id), ["Ordner/Unterordner/a.txt"])
    }
}

extension ArchiveEngineTests {
    func testAdditionalFormatsRoundTripsAndSelection() async throws {
        let (root, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = root.appendingPathComponent("other.txt")
        try Data("second".utf8).write(to: other)
        let engine = ArchiveEngine()
        for format in ["tar", "tar.gz", "tar.bz2", "tar.xz"] {
            let archive = root.appendingPathComponent("archive." + format)
            _ = try await engine.create(sources: [file, other], target: archive, format: format, level: "1", password: "")
            let listed = try await engine.list(archive)
            XCTAssertEqual(Set(listed.map(\.name)), Set([file.lastPathComponent, other.lastPathComponent]))
            _ = try await engine.test(archive, password: "")
            let destination = root.appendingPathComponent("out-" + format)
            _ = try await engine.extract(archive, destination: destination, password: "", selection: [file.lastPathComponent])
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(file.lastPathComponent)), try Data(contentsOf: file))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent(other.lastPathComponent).path))
            do { _ = try await engine.create(sources: [file], target: archive, format: format, level: "1", password: ""); XCTFail("Overwrite") } catch { }
            do { _ = try await engine.extract(archive, destination: destination, password: "", selection: []); XCTFail("Existing target") } catch { }
            if let alias = ["tar.gz": "tgz", "tar.bz2": "tbz2", "tar.xz": "txz"][format] {
                let renamed = root.appendingPathComponent("alias." + alias)
                try FileManager.default.copyItem(at: archive, to: renamed)
                let aliases = try await engine.list(renamed)
                XCTAssertEqual(aliases.count, 2)
            }
        }
    }
    func testWrappedUnsafePathsAndCancellation() async throws {
        let (root, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let malicious = root.appendingPathComponent("unsafe.tar.gz")
        let python = Process(); python.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        python.arguments = ["-c", "import tarfile,io,sys; t=tarfile.open(sys.argv[1],'w:gz'); i=tarfile.TarInfo('../escape'); i.size=1; t.addfile(i,io.BytesIO(b'x')); t.close()", malicious.path]
        try python.run(); python.waitUntilExit(); XCTAssertEqual(python.terminationStatus, 0)
        let destination = root.appendingPathComponent("unsafe-output")
        do { _ = try await ArchiveEngine().extract(malicious, destination: destination, password: "", selection: []); XCTFail("Unsafe inner TAR") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ArchiveEngine().create(sources: [file], target: root.appendingPathComponent("cancel.tar.xz"), format: "tar.xz", level: "1", password: "")
        }
        do { _ = try await task.value; XCTFail("Cancelled creation") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cancel.tar.xz").path))
        do { _ = try await ArchiveEngine().create(sources: [file], target: root.appendingPathComponent("secret.tar"), format: "tar", level: "1", password: "secret"); XCTFail("TAR password") } catch { }
    }
    func testAdditionalReadFixtures() async throws {
        #if SWIFT_PACKAGE
        let fixtureRoot = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        #else
        let fixtureRoot = Bundle(for: ArchiveEngineTests.self).resourceURL!.appendingPathComponent("Fixtures")
        #endif
        let (root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = ArchiveEngine()
        for ext in ["cab", "iso", "dmg", "tar.zst"] {
            let archive = fixtureRoot.appendingPathComponent("fixture." + ext)
            XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
            let entries = try await engine.list(archive)
            XCTAssertTrue(entries.contains { $0.name == "hello.txt" })
            let target = root.appendingPathComponent("read-" + ext)
            _ = try await engine.extract(archive, destination: target, password: "", selection: [])
            let files = FileManager.default.enumerator(at: target, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }
            let hello = try XCTUnwrap(files.first { $0.lastPathComponent == "hello.txt" })
            XCTAssertEqual(try Data(contentsOf: hello), Data("YA7 format fixture\n".utf8))
        }
        for ext in ["iso", "dmg"] {
            let broken = root.appendingPathComponent("invalid." + ext)
            try Data("Unsupported or encrypted image".utf8).write(to: broken)
            do { _ = try await engine.list(broken); XCTFail("Unsupported image must fail") } catch { }
        }
    }
    func testBareCompressionFormats() async throws {
        let (root, file) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = ArchiveEngine()
        for (format, suffix) in [("gzip", "gz"), ("bzip2", "bz2"), ("xz", "xz")] {
            let archive = root.appendingPathComponent("single.txt." + suffix)
            _ = try await engine.run(["a", "-t" + format, "--", archive.path, file.lastPathComponent], directory: root)
            let entries = try await engine.list(archive); XCTAssertEqual(entries.count, 1)
            let target = root.appendingPathComponent("bare-" + suffix)
            _ = try await engine.extract(archive, destination: target, password: "", selection: [])
            let files = try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)
            XCTAssertEqual(files.count, 1)
            XCTAssertEqual(try Data(contentsOf: files[0]), try Data(contentsOf: file))
        }
    }
    func testAllReadExtensionsRecognizedByFinder() throws {
        let (root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for ext in ["bz2", "bzip2", "zst", "cab", "iso", "dmg", "tgz", "tbz", "tbz2", "txz", "tzst"] {
            let url = root.appendingPathComponent("archive." + ext); try Data().write(to: url)
            XCTAssertNotNil(ArchiveFormat.recognizing(url.lastPathComponent))
            XCTAssertNoThrow(try FinderAction.extract.validate([url]))
        }
    }
}

@MainActor final class SevenZipUpdatesTests: XCTestCase {
    private func payload(_ version: String = "26.06") -> Data {
        Data("{\"tag_name\":\"\(version)\",\"html_url\":\"https://github.com/ip7z/7zip/releases/tag/\(version)\",\"draft\":false,\"prerelease\":false}".utf8)
    }
    private func preferences() -> UserDefaults { UserDefaults(suiteName: "YA7-VersionTests-" + UUID().uuidString)! }
    func testNumericVersionsAndInvalidAnswers() throws {
        XCTAssertTrue(try SevenZipRelease.decode(payload("26.10")).isNewer(than: "26.9"))
        XCTAssertFalse(try SevenZipRelease.decode(payload("26.05")).isNewer(than: "26.05"))
        XCTAssertFalse(try SevenZipRelease.decode(payload("25.09")).isNewer(than: "26.05"))
        XCTAssertThrowsError(try SevenZipRelease.decode(payload("invalid")))
        XCTAssertThrowsError(try SevenZipRelease.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try SevenZipRelease.decode(Data(String(decoding: payload(), as: UTF8.self).replacingOccurrences(of: "github.com", with: "example.com").utf8)))
    }
    func testScheduleManualOverrideAndDisabledChecks() async {
        var date = Date(timeIntervalSince1970: 1000000); var calls = 0
        let data = payload(); let defaults = preferences()
        let model = SevenZipUpdates(defaults: defaults, bundledVersion: "26.05", now: { date }) { request in
            calls += 1; XCTAssertEqual(request.timeoutInterval, 15)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await model.check(); XCTAssertEqual(calls, 1); XCTAssertNotNil(model.availableUpdate)
        await model.check(); XCTAssertEqual(calls, 1)
        await model.check(manual: true); XCTAssertEqual(calls, 2)
        date.addTimeInterval(SevenZipUpdates.week); await model.check(); XCTAssertEqual(calls, 3)
        model.automaticEnabled = false; date.addTimeInterval(SevenZipUpdates.week)
        await model.check(); XCTAssertEqual(calls, 3)
        let restored = SevenZipUpdates(defaults: defaults, bundledVersion: "26.05", now: { date }) { _ in XCTFail("No request expected"); throw URLError(.notConnectedToInternet) }
        XCTAssertFalse(restored.automaticEnabled); XCTAssertNotNil(restored.latest)
    }
    func testFailureBackoffPreservesLastSuccessAndManualError() async {
        var date = Date(timeIntervalSince1970: 1000000); var fail = false; var calls = 0
        let data = payload()
        let model = SevenZipUpdates(defaults: preferences(), bundledVersion: "26.05", now: { date }) { request in
            calls += 1
            if fail { throw URLError(.timedOut) }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await model.check(); let success = model.lastSuccess
        fail = true; date.addTimeInterval(SevenZipUpdates.week)
        await model.check(); XCTAssertNil(model.manualError); XCTAssertEqual(model.lastSuccess, success); XCTAssertNotNil(model.latest)
        await model.check(); XCTAssertEqual(calls, 2)
        date.addTimeInterval(SevenZipUpdates.retry); await model.check(); XCTAssertEqual(calls, 3)
        await model.check(manual: true); XCTAssertNotNil(model.manualError)
    }
    func testOfflineAndMalformedResponses() async {
        for kind in 0...2 {
            let model = SevenZipUpdates(defaults: preferences(), bundledVersion: "26.05") { request in
                if kind == 0 { throw URLError(.notConnectedToInternet) }
                return (Data("not json".utf8), HTTPURLResponse(url: request.url!, statusCode: kind == 1 ? 200 : 503, httpVersion: nil, headerFields: nil)!)
            }
            await model.check(manual: true)
            XCTAssertNotNil(model.manualError); XCTAssertNil(model.lastSuccess); XCTAssertNil(model.latest)
        }
    }
    func testConcurrentChecksShareRequest() async {
        var calls = 0; let data = payload()
        let model = SevenZipUpdates(defaults: preferences(), bundledVersion: "26.05") { request in
            calls += 1; try await Task.sleep(for: .milliseconds(40))
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        async let a: Void = model.check(manual: true)
        async let b: Void = model.check(manual: true)
        _ = await (a, b); XCTAssertEqual(calls, 1)
    }
}

final class LocalizationTests: XCTestCase {
    private func language(_ code: String) throws -> Bundle {
        try XCTUnwrap(Bundle(path: XCTUnwrap(Bundle.main.path(forResource: code, ofType: "lproj"))))
    }
    func testEnglishGermanAndEnglishFallback() throws {
        let en = try language("en"), de = try language("de")
        XCTAssertEqual(L10n.text("Create archive", bundle: en), "Create archive")
        XCTAssertEqual(L10n.text("Create archive", bundle: de), "Archiv erstellen")
        XCTAssertEqual(L10n.text("Unknown future message", bundle: en), "Unknown future message")
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        XCTAssertEqual(Bundle.preferredLocalizations(from: ["en", "de"], forPreferences: ["fr"]).first, "en")
    }
    func testAllTranslationKeysAndFormatArguments() throws {
        func table(_ bundle: Bundle) throws -> [String: String] {
            let path = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings"))
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let en = try table(language("en")), de = try table(language("de"))
        XCTAssertEqual(Set(en.keys), Set(de.keys)); XCTAssertGreaterThan(en.count, 180)
        for key in en.keys {
            XCTAssertEqual(en[key], key)
            XCTAssertFalse(try XCTUnwrap(de[key]).isEmpty)
            XCTAssertEqual(key.components(separatedBy: "%@").count, de[key]!.components(separatedBy: "%@").count)
        }
        let filename = "Grüße & [Entwurf].txt"
        let message = L10n.formatted("Archive created successfully.\n%@", arguments: [filename], bundle: try language("de"))
        XCTAssertEqual(message, "Archiv erfolgreich erstellt.\n" + filename)
        XCTAssertEqual(L10n.formatted("%@ item", arguments: [1], bundle: try language("de")), "1 Objekt")
        XCTAssertEqual(L10n.formatted("%@ items", arguments: [2], bundle: try language("en")), "2 items")
    }
    func testAboutAndProjectLicenseResources() throws {
        for code in ["en", "de"] {
            let bundle = try language(code)
            let credits = try XCTUnwrap(bundle.url(forResource: "Credits", withExtension: "rtf"))
            XCTAssertTrue(credits.path.contains(code + ".lproj"))
            let text = try String(contentsOf: credits)
            XCTAssertTrue(text.contains(code == "en" ? "Licenses and source code" : "Lizenzen und Quellcode"))
        }
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resources.appendingPathComponent("Credits.rtf").path))
        for name in ["YA7-License.txt", "YA7-Licensing.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: resources.appendingPathComponent("Legal/" + name).path))
        }
    }
    func testFinderBundleDisplayNamesAndResources() throws {
        for (name, english, german) in [("PackAction", "YA7: Compress", "YA7: Packen"), ("ExtractAction", "YA7: Extract", "YA7: Entpacken"), ("CheckAction", "YA7: Test", "YA7: Prüfen")] {
            let bundle = try XCTUnwrap(Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/" + name + ".appex")))
            XCTAssertEqual(bundle.developmentLocalization, "en")
            for (code, expected) in [("en", english), ("de", german)] {
                let path = try XCTUnwrap(bundle.path(forResource: code, ofType: "lproj"))
                let localized = try XCTUnwrap(Bundle(path: path))
                XCTAssertEqual(localized.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist"), expected)
                XCTAssertEqual(L10n.text("Extract", bundle: localized), code == "de" ? "Entpacken" : "Extract")
            }
            let extensionInfo = try XCTUnwrap(bundle.infoDictionary?["NSExtension"] as? [String: Any])
            let attributes = try XCTUnwrap(extensionInfo["NSExtensionAttributes"] as? [String: Any])
            XCTAssertNil(attributes["NSExtensionServiceFinderPreviewLabel"], "Use localized bundle display name as Finder fallback")
        }
    }
}
