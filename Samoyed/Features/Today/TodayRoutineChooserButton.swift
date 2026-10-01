import SwiftUI

struct TodayRoutineChooserButton: View {
    let dateTitle: String
    let title: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(dateTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(title ?? "No Routine")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.tint)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current Routine")
        .accessibilityValue(title ?? "No Routine")
        .accessibilityHint("Opens routine choices for \(dateTitle)")
        .accessibilityIdentifier("today-current-routine")
    }
}
