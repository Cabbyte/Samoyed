import SwiftUI

struct TodayAgendaFallback: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: TodayScreenModel
    let notes: [TimelineNote]
    let onSelectNote: (TimelineNote) -> Void
    let currentMinute: Int?
    let selectedBlockID: UUID?
    let selectedOpenSlotID: UUID?
    let dateNavigationScrollMinute: Int?
    let jumpToCurrentTrigger: Int
    let scrollToBlockID: UUID?
    let scrollToBlockTrigger: Int
    let onSelectBlock: (UUID) -> Void
    let onSelectOpenSlot: (UUID) -> Void

    @State private var lastInitialScrollDate: LocalDay?

    private var entries: [TodayAgendaEntry] {
        let blocks = model.blocks.map(TodayAgendaEntry.block)
        let openSlots = model.openSlots.map(TodayAgendaEntry.openSlot)
        let noteEntries = notes.map(TodayAgendaEntry.note)
        return (blocks + openSlots + noteEntries).sorted {
            if $0.startMinuteOfDay != $1.startMinuteOfDay {
                return $0.startMinuteOfDay < $1.startMinuteOfDay
            }
            if $0.sortDepth != $1.sortDepth {
                return $0.sortDepth < $1.sortDepth
            }
            return $0.id < $1.id
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(entries) { entry in
                        Button {
                            switch entry {
                            case let .block(block): onSelectBlock(block.id)
                            case let .openSlot(slot): onSelectOpenSlot(slot.id)
                            case let .note(note): onSelectNote(note)
                            }
                        } label: {
                            if case let .note(note) = entry {
                                TodayAgendaNoteRow(note: note)
                            } else {
                                TodayAgendaRow(
                                    entry: entry,
                                    isCurrent: entry.contains(minute: currentMinute),
                                    isSelected: entry.isSelected(
                                        blockID: selectedBlockID,
                                        openSlotID: selectedOpenSlotID
                                    )
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .id(entry.id)
                        .accessibilityIdentifier("timeline-\(entry.id)")
                    }
                } header: {
                    Text("Timeline")
                } footer: {
                    Text("Shown as an agenda so every title and time remains readable.")
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("today-accessibility-agenda")
            .task(id: model.date) {
                guard lastInitialScrollDate != model.date else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                lastInitialScrollDate = model.date
                scroll(
                    to: dateNavigationScrollMinute ?? currentMinute ?? model.initialScrollMinute,
                    proxy: proxy,
                    animated: false
                )
            }
            .onChange(of: jumpToCurrentTrigger) { _, _ in
                guard let currentMinute else { return }
                scroll(to: currentMinute, proxy: proxy, animated: true)
            }
            .onChange(of: scrollToBlockTrigger) { _, _ in
                guard let scrollToBlockID else { return }
                scroll(toID: "block-\(scrollToBlockID.uuidString)", proxy: proxy, animated: true)
            }
        }
    }

    private func scroll(to minute: Int, proxy: ScrollViewProxy, animated: Bool) {
        let target = entries.filter { $0.contains(minute: minute) }
            .max { $0.sortDepth < $1.sortDepth }
            ?? entries.first { $0.startMinuteOfDay >= minute }
            ?? entries.last
        guard let target else { return }
        scroll(toID: target.id, proxy: proxy, animated: animated)
    }

    private func scroll(toID id: String, proxy: ScrollViewProxy, animated: Bool) {
        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private struct TodayAgendaNoteRow: View {
    let note: TimelineNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.bubble")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Note")
                    Text(note.occurredAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(note.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full note")
    }
}

private enum TodayAgendaEntry: Identifiable {
    case block(TimelineBlockItem)
    case openSlot(TodayOpenSlotItem)
    case note(TimelineNote)

    var id: String {
        switch self {
        case let .block(block): "block-\(block.id.uuidString)"
        case let .openSlot(slot): "open-slot-\(slot.id.uuidString)"
        case let .note(note): "note-\(note.id.uuidString)"
        }
    }

    var startMinuteOfDay: Int {
        switch self {
        case let .block(block): block.startMinuteOfDay
        case let .openSlot(slot): slot.startMinuteOfDay
        case let .note(note): note.occurredAt.minuteOfDay
        }
    }

    var endMinuteOfDay: Int {
        switch self {
        case let .block(block): block.endMinuteOfDay
        case let .openSlot(slot): slot.endMinuteOfDay
        case let .note(note): note.occurredAt.minuteOfDay
        }
    }

    var sortDepth: Int {
        switch self {
        case let .block(block): block.layerIndex
        case .openSlot: -1
        case .note: Int.max
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
        case .note: false
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
        case .note: "Note"
        }
    }

    private var symbol: String {
        switch entry {
        case let .block(block):
            block.layerIndex == 0 ? "rectangle" : "rectangle.inset.filled"
        case .openSlot:
            "clock"
        case .note:
            "text.bubble"
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
