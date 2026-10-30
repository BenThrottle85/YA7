import SwiftUI

struct SevenZipUpdateSettings: View {
    @State private var updates = SevenZipUpdates.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text("Check 7-Zip version"), systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
            Text(L10n.format("Included version: %@", updates.bundledVersion)).font(.system(size: 12))
            Toggle(L10n.text("Check weekly while the app is open"), isOn: $updates.automaticEnabled)
                .font(.system(size: 12))
                .onChange(of: updates.automaticEnabled) { if updates.automaticEnabled { Task { await updates.check() } } }
            if let date = updates.lastSuccess {
                Text(L10n.format("Last successful check: %@", date.formatted(date: .abbreviated, time: .shortened)))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else { Text(L10n.text("Not checked yet.")).font(.system(size: 11)).foregroundStyle(.secondary) }
            if let latest = updates.latest {
                if updates.availableUpdate != nil {
                    Link(L10n.format("7-Zip %@ is available – view release", latest.version), destination: latest.url)
                        .font(.system(size: 12))
                } else if SevenZipRelease.components(updates.bundledVersion) == nil {
                    Text(L10n.format("Latest upstream version: %@", latest.version)).font(.system(size: 12))
                } else { Text(L10n.text("7-Zip is up to date.")).font(.system(size: 12)) }
            }
            if let error = updates.manualError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(L10n.text("Check now")) { Task { await updates.check(manual: true) } }.disabled(updates.checking)
                if updates.checking { ProgressView().controlSize(.small).accessibilityLabel(L10n.text("Checking version")) }
            }
            Text(L10n.text("Fetches only version information from the official 7-Zip project on GitHub."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SevenZipUpdateNotice: View {
    @State private var updates = SevenZipUpdates.shared
    var body: some View {
        if let release = updates.availableUpdate {
            HStack {
                Label(L10n.format("7-Zip %@ is available.", release.version), systemImage: "info.circle")
                Spacer()
                Link(L10n.text("View release"), destination: release.url)
            }.font(.system(size: 12)).padding(12).background(.bar)
        }
    }
}
