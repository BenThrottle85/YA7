import SwiftUI
import AppKit

struct DialogHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.09), in: .rect(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DialogCard<Content: View>: View {
    var inset: CGFloat = 14
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5) }
    }
}

struct DialogRow<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).frame(width: 15).accessibilityHidden(true)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 134, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DialogNote: View {
    let text: String
    var symbol = "info.circle"
    var warning = false
    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).accessibilityHidden(true)
        }
        .font(.system(size: 11))
        .foregroundStyle(warning ? Color.orange : Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct DocumentIcon: View {
    let name: String
    var isFolder = false
    var size: CGFloat = 22
    var symbol: String {
        if isFolder { return "folder.fill" }
        switch (name as NSString).pathExtension.lowercased() {
        case "7z", "zip", "rar", "tar", "gz", "xz": return "doc.zipper"
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff": return "photo"
        case "pdf": return "doc.richtext"
        case "txt", "md", "rtf": return "doc.text"
        case "csv", "xlsx", "numbers": return "tablecells"
        case "swift", "js", "json", "html", "css", "py": return "curlybraces.square"
        default: return "doc"
        }
    }
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(isFolder ? Color.accentColor : Color.secondary)
            .frame(width: size + 3, height: size + 4)
            .accessibilityHidden(true)
    }
}

struct ArchiveSummary: View {
    let name: String
    let detail: String
    var symbol = "doc.zipper"
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 27)).foregroundStyle(.secondary)
                .frame(width: 34).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(2).truncationMode(.middle)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FolderPickerRow: View {
    @Binding var path: String
    var body: some View {
        HStack(spacing: 8) {
            Text(path.isEmpty ? L10n.text("Choose a folder") : URL(fileURLWithPath: path).lastPathComponent)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L10n.text("Choose…")) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                panel.prompt = L10n.text("Choose")
                if panel.runModal() == .OK, let url = panel.url { path = url.path }
            }
            .accessibilityLabel(L10n.text("Choose destination folder"))
        }.help(path)
    }
}

struct PasswordField: View {
    @Binding var password: String
    @State private var visible = false
    var body: some View {
        HStack(spacing: 8) {
            Group {
                if visible { TextField(L10n.text("Optional"), text: $password) }
                else { SecureField(L10n.text("Optional"), text: $password) }
            }
            .textFieldStyle(.roundedBorder).labelsHidden().accessibilityLabel(L10n.text("Password"))
            Button { visible.toggle() } label: {
                Image(systemName: visible ? "eye.slash" : "eye")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(visible ? L10n.text("Hide password") : L10n.text("Show password"))
            .accessibilityLabel(visible ? L10n.text("Hide password") : L10n.text("Show password"))
        }
    }
}

struct ArchiveFormatPicker: View {
    @Binding var selection: String
    var body: some View {
        Picker(L10n.text("Format"), selection: $selection) {
            ForEach(ArchiveFormat.writableFormats) { format in Text(format.title).tag(format.id) }
        }.labelsHidden()
    }
}
