import SwiftUI

struct TaskPreviewCard: View {
    let task: SavedTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.body.weight(.medium))
                .lineLimit(3)

            if let body = task.body {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            Text(task.savedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
