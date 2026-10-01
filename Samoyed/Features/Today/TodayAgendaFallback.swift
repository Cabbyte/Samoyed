import SwiftUI

struct TodayAgendaFallback: View {
    let model: TodayScreenModel
    let notes: [TimelineNote]
    let onSelectNote: (TimelineNote) -> Void
    let currentMinute: Int?
    let selectedBlockID: UUID?
    let selectedOpenSlotID: UUID?
    let onSelectBlock: (UUID) -> Void
    let onSelectOpenSlot: (UUID) -> Void

    private var entries: [TodayAgendaEntry] {
        let blocks = model.blocks.map(TodayAgendaEntry.block)
        let openSlots = model.openSlots.map(TodayAgendaEntry.openSlot)
        return (blocks + openSlots).sorted {
            if $0.startMinuteOfDay != $1.startMinuteOfDay {
                return $0.startMinuteOfDay < $1.startMinuteOfDay
            }
            return $0.sortDepth < $1.sortDepth
        }
    }

    var body: some View {
        List {
            if !notes.isEmpty {
                Section("Notes") {
                    ForEach(notes) { note in
                        Button { onSelectNote(note) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.occurredAt, style: .time)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(note.text).foregroundStyle(.primary)
                            }
                        }
                        .accessibilityIdentifier("timeline-note-\(note.id.uuidString)")
                    }
                }
            }
            Section {
                ForEach(entries) { entry in
                    Button {
                        switch entry {
                        case let .block(block):
                            onSelectBlock(block.id)
                        case let .openSlot(slot):
                            onSelectOpenSlot(slot.id)
                        }
                    } label: {
                        TodayAgendaRow(
                            entry: entry,
                            isCurrent: entry.contains(minute: currentMinute),
                            isSelected: entry.isSelected(
                                blockID: selectedBlockID,
                                openSlotID: selectedOpenSlotID
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Timeline")
            } footer: {
                Text("Shown as an agenda so every title and time remains readable.")
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("today-accessibility-agenda")
    }
}

private enum TodayAgendaEntry: Identifiable {
    case block(TimelineBlockItem)
    case openSlot(TodayOpenSlotItem)

    var id: String {
        switch self {
        case let .block(block): "block-\(block.id.uuidString)"
        case let .openSlot(slot): "open-slot-\(slot.id.uuidString)"
        }
    }

    var startMinuteOfDay: Int {
        switch self {
        case let .block(block): block.startMinuteOfDay
        case let .openSlot(slot): slot.startMinuteOfDay
        }
    }

    var endMinuteOfDay: Int {
        switch self {
        case let .block(block): block.endMinuteOfDay
        case let .openSlot(slot): slot.endMinuteOfDay
        }
    }

    var sortDepth: Int {
        switch self {
        case let .block(block): block.layerIndex
        case .openSlot: -1
        }
    }

    func contains(minute: Int?) -> Bool {
        guard let minute else { return false }
        return (startMinuteOfDay ..< endMinuteOfDay).contains(minute)
    }

    func isSelected(blockID: UUID?, openSlotID: UUID?) -> Bool {
        switch self {
        case let .block(block): block.id == blockID
        case let .openSlot(slot): slot.id == openSlotID
        }
    }
}

private struct TodayAgendaRow: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let entry: TodayAgendaEntry
    let isCurrent: Bool
    let isSelected: Bool

    private var titleLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                titleLayout {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isCurrent {
                        Text("NOW")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(differentiateWithoutColor ? Color.primary : Color.accentColor)
                    }
                }

                Text("\(entry.startMinuteOfDay.formattedTime)–\(entry.endMinuteOfDay.formattedTime)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(differentiateWithoutColor ? Color.primary : Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows details")
    }

    private var title: String {
        switch entry {
        case let .block(block): block.title
        case .openSlot: "Open Time"
        }
    }

    private var symbol: String {
        switch entry {
        case let .block(block):
            block.layerIndex == 0 ? "rectangle" : "rectangle.inset.filled"
        case .openSlot:
            "clock"
        }
    }

    private var detail: String? {
        switch entry {
        case let .block(block) where block.incompleteTaskCount > 0:
            return "\(block.incompleteTaskCount) checklist item\(block.incompleteTaskCount == 1 ? "" : "s") remaining"
        case let .block(block) where block.layerIndex > 0:
            return "Overlay level \(block.layerIndex)"
        default:
            return nil
        }
    }

    private var accessibilityValue: String {
        [isCurrent ? "Current" : nil, isSelected ? "Selected" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
