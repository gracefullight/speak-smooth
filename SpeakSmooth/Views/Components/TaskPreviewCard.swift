import SwiftUI
import AppKit

struct TaskPreviewCard: View {
    let task: SavedTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.body.weight(.medium))
                .lineLimit(3)
                .textSelection(.enabled)

            if let body = task.body {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .textSelection(.enabled)
                    .help(body)
            }

            HStack {
                Text(task.savedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(task.title, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .help("Copy sentence")
                .accessibilityLabel("Copy sentence")
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple-reminderkit://")!)
                } label: { Image(systemName: "arrow.up.forward.app") }
                .help("Open Reminders")
                .accessibilityLabel("Open Reminders")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
