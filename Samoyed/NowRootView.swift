import SwiftUI

struct NowRootView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(SamoyedStore.self) private var store
    @State private var taskFilter: NowTaskFilter = .all
    @State private var pendingUndoReferences: [TaskCompletionReference] = []
    @State private var feedbackContext: FeedbackSheetContext?
    @State private var completionFeedbackTrigger = 0

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let referenceDate = SamoyedSimulationClock.adjusted(context.date)
                let localDay = LocalDay(date: referenceDate)

                Group {
                    if !store.isLoaded {
                        ScreenLoadingView(
                            title: "Loading Now",
                            systemImage: "bolt.circle",
                            description: "Refreshing your current blocks, notes, and checklist."
                        )
                    } else {
                        RootScreenContainer(
                            isLoaded: true,
                            loadingTitle: "Loading Now",
                            loadingSystemImage: "bolt.circle",
                            loadingDescription: "Refreshing your current blocks, notes, and checklist.",
                            errorTitle: "Unable to Load Now",
                            retry: store.reload,
                            load: { try store.nowScreenModel(at: referenceDate) }
                        ) { model in
                            NowContentView(
                                model: model,
                                taskFilter: taskFilter,
                                onChooseRoutine: {
                                    store.openLibrary(destination: .routines)
                                },
                                onFeedback: {
                                    feedbackContext = FeedbackSheetContext(
                                        target: model.focusBlock.map {
                                            .block(blockID: $0.id)
                                        } ?? .wholeDay,
                                        targetTitle: model.focusBlock?.title ?? "Whole Day",
                                        targetDetail: model.focusBlock.map {
                                            "Current block, \($0.startMinuteOfDay.formattedTime) to \($0.endMinuteOfDay.formattedTime)"
                                        } ?? model.date.titleText,
                                        localDay: model.date,
                                        source: .now
                                    )
                                },
                                onToggleTask: { blockID, taskID in
                                    toggleTask(on: model.date, blockID: blockID, taskID: taskID)
                                }
                            )
                        }
                    }
                }
                .navigationTitle(localDay.nowNavigationTitle)
            }
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            store.startCurrentBlockLiveActivity(
                                referenceDate: SamoyedSimulationClock.adjusted(.now)
                            )
                        } label: {
                            Label("Start Live Activity", systemImage: "waveform.path.ecg.rectangle")
                        }

                        Picker("Checklist Filter", selection: $taskFilter) {
                            ForEach(NowTaskFilter.allCases) { filter in
                                Label(filter.title, systemImage: filter.systemImage)
                                    .tag(filter)
                            }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !pendingUndoReferences.isEmpty {
                Button("Undo", action: undoTaskCompletion)
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background {
                        if reduceTransparency {
                            Color(uiColor: .systemBackground)
                        } else {
                            Rectangle().fill(.bar)
                        }
                    }
            }
        }
        .sheet(item: $feedbackContext) { context in
            FeedbackSheet(context: context) { sentiment, note in
                try store.saveFeedback(
                    target: context.target,
                    on: context.localDay,
                    sentiment: sentiment,
                    note: note,
                    source: context.source
                )
            }
        }
        .sensoryFeedback(.success, trigger: completionFeedbackTrigger)
    }

    private func toggleTask(on date: LocalDay, blockID: UUID, taskID: UUID) {
        do {
            if let reference = try store.completeTask(
                on: date,
                blockID: blockID,
                taskID: taskID
            ) {
                pendingUndoReferences = [reference]
                completionFeedbackTrigger += 1
            } else {
                store.toggleTask(on: date, blockID: blockID, taskID: taskID)
                pendingUndoReferences = []
            }
        } catch {
            store.presentError(error)
        }
    }

    private func undoTaskCompletion() {
        do {
            try store.undoTaskCompletions(pendingUndoReferences)
            pendingUndoReferences = []
        } catch {
            store.presentError(error)
        }
    }
}

private enum NowTaskFilter: String, CaseIterable, Identifiable {
    case all
    case remaining
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Items"
        case .remaining: "Remaining"
        case .completed: "Completed"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "list.bullet"
        case .remaining: "circle"
        case .completed: "checkmark.circle"
        }
    }
}

private struct NowContentView: View {
    let model: NowScreenModel
    let taskFilter: NowTaskFilter
    let onChooseRoutine: () -> Void
    let onFeedback: () -> Void
    let onToggleTask: (UUID, UUID) -> Void

    var body: some View {
        ScrollView {
            if model.focusState == .noRoutine {
                ContentUnavailableView {
                    Label("No Routine Today", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Choose an existing routine to give Now a trusted local plan to run.")
                } actions: {
                    Button("Choose Routine", action: onChooseRoutine)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
                .padding(.horizontal, 20)
            } else {
                LazyVStack(alignment: .leading, spacing: 26) {
                    NowCurrentSection(model: model, onFeedback: onFeedback)

                    if !model.noteSections.isEmpty {
                        NowNotesSection(sections: model.noteSections)
                    }

                    NowTasksSection(
                        sections: model.taskSections,
                        filter: taskFilter,
                        statusMessage: model.statusMessage,
                        focusState: model.focusState,
                        onToggle: onToggleTask
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct NowCurrentSection: View {
    let model: NowScreenModel
    let onFeedback: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CURRENT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button(action: onFeedback) {
                    Label("Feedback", systemImage: "bubble.left")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("now-feedback")
            }

            NowBlockStack(
                items: Array(model.activeChain.prefix(3)),
                notes: model.noteSections
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NowBlockStack: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let items: [NowChainItem]
    let notes: [NowNoteSection]

    var body: some View {
        if items.isEmpty {
            NowOpenTimeCard()
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NowBlockCard(
                        item: item,
                        summary: notes.first(where: { $0.id == item.id })?.note,
                        isFront: index == 0,
                        overlapsPreviousCard: false
                    )
                }
            }
        } else {
            VStack(spacing: -22) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NowBlockCard(
                        item: item,
                        summary: notes.first(where: { $0.id == item.id })?.note,
                        isFront: index == 0,
                        overlapsPreviousCard: true
                    )
                    .zIndex(Double(items.count - index))
                }
            }
        }
    }
}

private struct NowBlockCard: View {
    @Environment(\.samoyedTintPreset) private var tintPreset

    let item: NowChainItem
    let summary: String?
    let isFront: Bool
    let overlapsPreviousCard: Bool

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: item.layerIndex,
            isBlank: item.isBlank,
            preset: tintPreset
        )
    }

    private var symbol: String {
        if item.isBlank { return "clock" }
        switch item.layerIndex {
        case 0: return "sun.max"
        case 1: return "bolt.fill"
        default: return "sparkles"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(isFront ? style.accentForeground : Color.secondary)
                .frame(width: 52, height: 52)
                .background(
                    isFront ? style.accent : Color(uiColor: .tertiarySystemFill),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.isBlank ? "Open Time" : item.title)
                        .font(.headline)
                        .lineLimit(2)

                    Spacer(minLength: 6)

                    Text("\(item.startMinuteOfDay.formattedTime)–\(item.endMinuteOfDay.formattedTime)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFront ? style.accent : Color.secondary)
                        .lineLimit(1)
                }

                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, isFront || !overlapsPreviousCard ? 16 : 32)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

            shape
                .fill(isFront ? style.strongSurface : style.surface.opacity(0.96))
                .overlay {
                    if isFront {
                        shape.fill(style.accent.opacity(0.08))
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isFront ? style.accent.opacity(0.9) : Color(uiColor: .separator).opacity(0.18),
                    lineWidth: isFront ? 1.25 : 0.75
                )
        }
        .shadow(
            color: Color.black.opacity(isFront ? 0.08 : 0.045),
            radius: isFront ? 12 : 7,
            y: isFront ? 6 : 3
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.startMinuteOfDay.formattedTime) to \(item.endMinuteOfDay.formattedTime)")
    }
}

private struct NowOpenTimeCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Open Time")
                    .font(.headline)
                Text("No block is active right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }
}

private struct NowNotesSection: View {
    @Environment(\.samoyedTintPreset) private var tintPreset

    let sections: [NowNoteSection]

    private var containerStyle: LayerVisualStyle {
        let depth = sections.map(\.layerIndex).max() ?? 0
        return LayerVisualStyle.forBlock(layerIndex: depth, isBlank: false, preset: tintPreset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    NowNoteRow(section: section)

                    if index < sections.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(
                containerStyle.surface.opacity(0.7),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(containerStyle.border.opacity(0.2), lineWidth: 0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NowNoteRow: View {
    @Environment(\.samoyedTintPreset) private var tintPreset

    let section: NowNoteSection

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: section.layerIndex,
            isBlank: section.isBlank,
            preset: tintPreset
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(style.accent)

            Text(section.note)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NowTasksSection: View {
    let sections: [NowTaskSection]
    let filter: NowTaskFilter
    let statusMessage: String?
    let focusState: NowFocusState
    let onToggle: (UUID, UUID) -> Void

    private var allTasks: [NowChecklistDisplayItem] {
        NowChecklistDisplayBuilder.sortedItems(from: sections)
    }

    private var visibleTasks: [NowChecklistDisplayItem] {
        switch filter {
        case .all: allTasks
        case .remaining: allTasks.filter { !$0.task.isCompleted }
        case .completed: allTasks.filter { $0.task.isCompleted }
        }
    }

    private var visibleGroups: [NowChecklistDisplayGroup] {
        NowChecklistDisplayBuilder.groups(from: visibleTasks)
    }

    private var emptyDescription: String {
        guard statusMessage != "No incomplete tasks in this chain." else {
            return "No incomplete checklist items in this chain."
        }

        return statusMessage ?? "The current block has no matching checklist items."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today’s Actions")
                    .font(.headline)

                Spacer()

                if !allTasks.isEmpty {
                    Text("\(allTasks.filter { !$0.task.isCompleted }.count) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if visibleTasks.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleGroups) { group in
                        NowTaskGroup(group: group) { row in
                            onToggle(row.blockID, row.task.id)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyTitle: String {
        if filter == .completed {
            return "No Completed Items"
        }
        if focusState == .finished || (!allTasks.isEmpty && allTasks.allSatisfy(\.task.isCompleted)) {
            return "You’re All Caught Up"
        }
        return "No Checklist Items Right Now"
    }

    private var emptySystemImage: String {
        emptyTitle == "You’re All Caught Up" ? "checkmark.circle" : "checklist"
    }
}

private struct NowTaskGroup: View {
    @Environment(\.samoyedTintPreset) private var tintPreset

    let group: NowChecklistDisplayGroup
    let onToggle: (NowChecklistDisplayItem) -> Void

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: group.layerIndex,
            isBlank: false,
            preset: tintPreset
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, row in
                NowTaskRow(row: row) {
                    onToggle(row)
                }

                if index < group.items.count - 1 {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .background(group.isCompleted ? Color(uiColor: .secondarySystemBackground) : style.surface)
        .clipShape(shape)
        .overlay {
            shape.stroke(
                group.isCompleted
                    ? Color(uiColor: .separator).opacity(0.12)
                    : style.border.opacity(0.2),
                lineWidth: 0.75
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "now-checklist-group-layer-\(group.layerIndex)-\(group.isCompleted ? "completed" : "remaining")"
        )
    }
}

private struct NowTaskRow: View {
    @Environment(\.samoyedTintPreset) private var tintPreset

    let row: NowChecklistDisplayItem
    let onToggle: () -> Void

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(layerIndex: row.layerIndex, isBlank: false, preset: tintPreset)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: row.task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.task.isCompleted ? Color.secondary : style.accent)
                    .contentTransition(.symbolEffect(.replace))

                Text(row.task.title)
                    .font(.body)
                    .strikethrough(row.task.isCompleted, color: .secondary)
                    .foregroundStyle(row.task.isCompleted ? .secondary : .primary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.task.title)
        .accessibilityValue(row.task.isCompleted ? "Completed" : "Not completed")
        .accessibilityHint("Toggles this checklist item")
    }
}

#Preview("Now") {
    NowRootView()
        .environment(PreviewSupport.store(tab: .now))
}

#Preview("Now Loading") {
    NowRootView()
        .environment(PreviewSupport.store(tab: .now, loaded: false))
}
