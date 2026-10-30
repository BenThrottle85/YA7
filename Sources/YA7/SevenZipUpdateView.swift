import SwiftUI

struct SevenZipUpdateSettings: View {
    @State private var updates = SevenZipUpdates.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("7-Zip-Version prüfen", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
            Text("Enthaltene Version: \(updates.bundledVersion)").font(.system(size: 12))
            Toggle("Wöchentlich bei geöffneter App prüfen", isOn: $updates.automaticEnabled)
                .font(.system(size: 12))
                .onChange(of: updates.automaticEnabled) { if updates.automaticEnabled { Task { await updates.check() } } }
            if let date = updates.lastSuccess {
                Text("Zuletzt erfolgreich: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else { Text("Noch nicht geprüft.").font(.system(size: 11)).foregroundStyle(.secondary) }
            if let latest = updates.latest {
                if updates.availableUpdate != nil {
                    Link("7-Zip \(latest.version) ist verfügbar – Veröffentlichung ansehen", destination: latest.url)
                        .font(.system(size: 12))
                } else if SevenZipRelease.components(updates.bundledVersion) == nil {
                    Text("Aktuelle Herstellerversion: \(latest.version)").font(.system(size: 12))
                } else { Text("7-Zip ist auf dem aktuellen Stand.").font(.system(size: 12)) }
            }
            if let error = updates.manualError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Jetzt prüfen") { Task { await updates.check(manual: true) } }.disabled(updates.checking)
                if updates.checking { ProgressView().controlSize(.small).accessibilityLabel("Version wird geprüft") }
            }
            Text("Ruft nur Versionsinformationen beim offiziellen 7-Zip-Projekt auf GitHub ab.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SevenZipUpdateNotice: View {
    @State private var updates = SevenZipUpdates.shared
    var body: some View {
        if let release = updates.availableUpdate {
            HStack {
                Label("7-Zip \(release.version) ist verfügbar.", systemImage: "info.circle")
                Spacer()
                Link("Veröffentlichung ansehen", destination: release.url)
            }.font(.system(size: 12)).padding(12).background(.bar)
        }
    }
}
