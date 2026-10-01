import SwiftUI
import UIKit

struct TodayRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SamoyedStore.self) private var store

    @State private var noteDraft: TimelineNote?
    @State private var selection: TodaySelection?
    @State private var jumpToCurrentTrigger = 0
    @State private var scrollToBlockTrigger = 0
    @State private var scrollToBlockID: UUID?
    @State private var dateNavigationScrollMinute: Int?
    @State private var isShowingRoutineChooser = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let referenceDate = SamoyedSimulationClock.adjusted(context.date)
                if !store.isLoaded {
                    ScreenLoadingView(
                        title: "Loading Today",
                        systemImage: "calendar",
                        description: "Preparing your timeline and current context."
                    )
                } else {
                    RootScreenContainer(
                        isLoaded: true,
                        loadingTitle: "Loading Today",
                        loadingSystemImage: "calendar",
                        loadingDescription: "Preparing your timeline and current context.",
                        errorTitle: "Unable to Load Today",
                        retry: store.reload
                    ) {
                        try store.todayScreenModel(
                            currentDate: referenceDate
                        )
                    } content: { model in
                        timelineContent(model: model, referenceDate: referenceDate)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Add Note", systemImage: "square.and.pencil") {
                        noteDraft = TimelineNote(text: "", occurredAt: store.selectedDate.date(minuteOfDay: Date.now.minuteOfDay) ?? .now)
                    }
                }
            }
            .sheet(item: $noteDraft) { note in TimelineNoteEditor(note: note).environment(store) }
            .navigationTitle(store.selectedDate.titleText)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: store.selectedDate) { _, _ in
            selection = store.selectedBlockID.map { .block(id: $0) }
        }
        .onChange(of: store.selectedBlockID) { _, newValue in
            guard let blockID = newValue else { return }
            selection = .block(id: blockID)
        }
        .onChange(of: store.selectedTab) { _, newValue in
            guard newValue != .today else { return }
            selection = nil
        }
        .onChange(of: selection) { _, newValue in
            if newValue == nil {
                store.selectBlock(nil)
            }
        }
    }

    private func timelineContent(model: TodayScreenModel, referenceDate: Date) -> some View {
        let currentMinute = store.currentMinuteOnSelectedDate(currentDate: referenceDate)
        let currentRoutine = try? store.todayTemplateChooserModel(for: model.date).currentSelection

        return Group {
            if currentRoutine == nil && model.blocks.isEmpty && store.document.timelineNotes(on: model.date).isEmpty {
                ContentUnavailableView {
                    Label("No Routine Selected", systemImage: "calendar.badge.minus")
                } description: {
                    Text("This is a valid open day. Choose a routine if you want a structured timeline.")
                } actions: {
                    Button("Choose Routine") {
                        isShowingRoutineChooser = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                TodayTimelineView(
                    model: model,
                    notes: store.document.timelineNotes(on: model.date),
                    onSelectNote: { noteDraft = $0 },
                    selectedBlockID: selection?.blockID,
                    selectedOpenSlotID: selection?.openSlotID,
                    currentMinute: currentMinute,
                    dateNavigationScrollMinute: dateNavigationScrollMinute,
                    jumpToCurrentTrigger: jumpToCurrentTrigger,
                    scrollToBlockID: scrollToBlockID,
                    scrollToBlockTrigger: scrollToBlockTrigger,
                    timingResolver: { blockID in
                        store.persistedBlock(on: store.selectedDate, blockID: blockID)?.timing
                    },
                    onSelectBlock: handleBlockSelection,
                    onSelectOpenSlot: handleOpenSlotSelection,
                    onClearSelection: clearSelection
                )
                .sheet(item: $selection) { presentedSelection in
                    inspector(for: presentedSelection, model: model)
                }
            }
        }
        .sheet(isPresented: $isShowingRoutineChooser) {
            NavigationStack {
                TodayTemplateChooserView(date: model.date) {
                    isShowingRoutineChooser = false
                }
                .navigationTitle("Choose Routine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isShowingRoutineChooser = false
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TodayRoutineChooserButton(dateTitle: model.date.titleText, title: currentRoutine?.title) {
                    isShowingRoutineChooser = true
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    preserveTimelinePosition(model: model, currentMinute: currentMinute)
                    store.moveSelectedDate(by: -1)
                } label: {
                    Label("Previous Day", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Previous Day")
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if store.selectedDate == .today() {
                    Button {
                        jumpToCurrent()
                    } label: {
                        Label("Jump to Now", systemImage: "location")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Jump to current time")
                } else {
                    Button("Today") {
                        store.selectDate(.today())
                    }
                    .accessibilityLabel("Go to Today")
                }

                Button {
                    preserveTimelinePosition(model: model, currentMinute: currentMinute)
                    store.moveSelectedDate(by: 1)
                } label: {
                    Label("Next Day", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Next Day")
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selection)
        .task(id: model.date) {
            syncSelectionForDisplayedDate(using: model)
        }
        .onChange(of: model.blocks.map(\.id)) { _, _ in
            validateSelection(using: model)
        }
        .onChange(of: model.openSlots.map(\.id)) { _, _ in
            validateSelection(using: model)
        }
    }

    @ViewBuilder
    private func inspector(for presentedSelection: TodaySelection, model: TodayScreenModel) -> some View {
        NavigationStack {
            inspectorContent(for: presentedSelection, model: model)
        }
    }

    @ViewBuilder
    private func inspectorContent(for presentedSelection: TodaySelection, model: TodayScreenModel) -> some View {
        switch presentedSelection {
        case let .block(id):
            if let detail = selectedBlockDetail(for: id) {
                TodayBlockInspectorView(
                    date: model.date,
                    detail: detail,
                    onSelectParent: {
                        selectParentBlock(from: detail)
                    },
                    onToggleTask: { taskID in
                        store.toggleTask(on: model.date, blockID: detail.id, taskID: taskID)
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Add Note", systemImage: "square.and.pencil") {
                            selection = nil
                            noteDraft = TimelineNote(text: "", occurredAt: model.date.date(minuteOfDay: Date.now.minuteOfDay) ?? .now, blockInstanceID: detail.id)
                        }
                    }
                }
            } else if let block = model.blocks.first(where: { $0.id == id }) {
                TodayUnavailableInspectorView(
                    title: block.title,
                    startMinuteOfDay: block.startMinuteOfDay,
                    endMinuteOfDay: block.endMinuteOfDay
                )
            }

        case let .openSlot(id):
            if let slot = model.openSlots.first(where: { $0.id == id }) {
                TodayOpenSlotInspectorView(slot: slot)
            }
        }
    }

    private func syncSelectionForDisplayedDate(using model: TodayScreenModel) {
        guard model.date == store.selectedDate else { return }

        switch selection {
        case .none:
            if let blockID = store.selectedBlockID, model.blocks.contains(where: { $0.id == blockID }) {
                selection = .block(id: blockID)
            }

        case let .block(id) where model.blocks.contains(where: { $0.id == id }):
            store.selectBlock(id)

        case let .openSlot(id) where model.openSlots.contains(where: { $0.id == id }):
            store.selectBlock(nil)

        default:
            if let blockID = store.selectedBlockID, model.blocks.contains(where: { $0.id == blockID }) {
                selection = .block(id: blockID)
            } else {
                selection = nil
            }
        }
    }

    private func validateSelection(using model: TodayScreenModel) {
        switch selection {
        case .none:
            return

        case let .block(id):
            guard model.blocks.contains(where: { $0.id == id }) else {
                selection = nil
                store.selectBlock(nil)
                return
            }

        case let .openSlot(id):
            guard model.openSlots.contains(where: { $0.id == id }) else {
                selection = nil
                return
            }
        }
    }

    private func jumpToCurrent() {
        let blockID = store.currentActiveBlockID(
            currentDate: SamoyedSimulationClock.adjusted(.now)
        )
        store.selectBlock(blockID)
        selection = blockID.map { .block(id: $0) }
        jumpToCurrentTrigger += 1
    }

    private func preserveTimelinePosition(
        model: TodayScreenModel,
        currentMinute: Int?
    ) {
        dateNavigationScrollMinute = currentMinute
            ?? dateNavigationScrollMinute
            ?? model.initialScrollMinute
    }

    private func handleBlockSelection(_ blockID: UUID) {
        store.selectBlock(blockID)
        selection = .block(id: blockID)
    }

    private func handleOpenSlotSelection(_ slotID: UUID) {
        store.selectBlock(nil)
        selection = .openSlot(id: slotID)
    }

    private func clearSelection() {
        selection = nil
        store.selectBlock(nil)
    }

    private func selectParentBlock(from detail: BlockDetailModel) {
        guard let parentID = detail.parentBlockID else { return }
        store.selectBlock(parentID)
        selection = .block(id: parentID)
        scrollToBlockID = parentID
        scrollToBlockTrigger += 1
    }

    private func selectedBlockDetail(for blockID: UUID) -> BlockDetailModel? {
        guard let detail = try? store.blockDetailModel(on: store.selectedDate, blockID: blockID) else {
            return nil
        }
        return detail
    }

}

private enum TodaySelection: Identifiable, Equatable {
    case block(id: UUID)
    case openSlot(id: UUID)

    var id: String {
        switch self {
        case let .block(id):
            return "block-\(id.uuidString)"
        case let .openSlot(id):
            return "open-slot-\(id.uuidString)"
        }
    }

    var blockID: UUID? {
        guard case let .block(id) = self else { return nil }
        return id
    }

    var openSlotID: UUID? {
        guard case let .openSlot(id) = self else { return nil }
        return id
    }
}

private struct TodayTimelineScale {
    private let mapping: TimelineElasticTimeScale

    init(
        model: TodayScreenModel,
        currentMinute: Int?,
        readableIntervals: [TimelineElasticTimeScale.ReadableInterval] = []
    ) {
        mapping = TimelineElasticTimeScale(
            blocks: model.blocks,
            openSlots: model.openSlots,
            currentMinute: currentMinute,
            readableIntervals: readableIntervals
        )
    }

    var startHour: Int {
        mapping.startHour
    }

    var endHour: Int {
        mapping.endHour
    }

    var topInset: CGFloat {
        CGFloat(mapping.topInset)
    }

    var bottomInset: CGFloat {
        CGFloat(mapping.bottomInset)
    }

    var hours: [Int] {
        mapping.hours
    }

    var canvasHeight: CGFloat {
        CGFloat(mapping.canvasHeight)
    }

    func yPosition(for minute: Int) -> CGFloat {
        CGFloat(mapping.yPosition(for: minute))
    }

    func distance(from startMinute: Int, to endMinute: Int) -> CGFloat {
        CGFloat(mapping.distance(from: startMinute, to: endMinute))
    }

    func hourHeight(for hour: Int) -> CGFloat {
        CGFloat(mapping.hourHeight(for: hour))
    }
}

private struct TodayTimelineScrollAnchor: Hashable {
    let minute: Int
}

private struct TodayTimelineView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: TodayScreenModel
    let notes: [TimelineNote]
    let onSelectNote: (TimelineNote) -> Void
    let selectedBlockID: UUID?
    let selectedOpenSlotID: UUID?
    let currentMinute: Int?
    let dateNavigationScrollMinute: Int?
    let jumpToCurrentTrigger: Int
    let scrollToBlockID: UUID?
    let scrollToBlockTrigger: Int
    let timingResolver: (UUID) -> TimeBlockTiming?
    let onSelectBlock: (UUID) -> Void
    let onSelectOpenSlot: (UUID) -> Void
    let onClearSelection: () -> Void

    @State private var lastInitialScrollDate: LocalDay?
    @State private var timelineWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .headline) private var headlinePointSize: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var footnotePointSize: CGFloat = 13

    private let labelWidth: CGFloat = 52
    private let trackLeadingInset: CGFloat = 12
    private let trackTrailingInset: CGFloat = 22

    private var scale: TodayTimelineScale {
        TodayTimelineScale(
            model: model,
            currentMinute: currentMinute,
            readableIntervals: readableIntervals
        )
    }

    private var readableIntervals: [TimelineElasticTimeScale.ReadableInterval] {
        guard timelineWidth > 0 else { return [] }
        let titleFont = UIFont.systemFont(ofSize: headlinePointSize, weight: .semibold)
        let timeFont = UIFont.systemFont(ofSize: footnotePointSize)
        let heights = model.blocks.map { block -> (UUID, Double) in
            var width = timelineWidth - labelWidth - trackLeadingInset - trackTrailingInset
            for _ in 0 ..< block.layerIndex {
                width -= min(16, max(8, width * 0.12)) + min(8, max(4, width * 0.06))
            }
            let titleHeight = (block.title as NSString).boundingRect(
                with: CGSize(width: max(1, width - 24), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: titleFont],
                context: nil
            ).height
            let lines: CGFloat = titleHeight > titleFont.lineHeight + 1 ? 2 : 1
            return (block.id, Double(max(lines == 1 ? 68 : 96,
                ceil(titleFont.lineHeight * lines + timeFont.lineHeight + 26))))
        }
        return TimelineReadability.intervals(
            blocks: model.blocks,
            openSlots: model.openSlots,
            headerHeights: Dictionary(uniqueKeysWithValues: heights),
            openSlotHeight: Double(ceil(titleFont.lineHeight + timeFont.lineHeight + 26))
        )
    }

    var body: some View {
        if voiceOverEnabled || dynamicTypeSize.isAccessibilitySize
            || TimelineReadability.requiresAgenda(blocks: model.blocks) {
            TodayAgendaFallback(
                model: model,
                notes: notes,
                onSelectNote: onSelectNote,
                currentMinute: currentMinute,
                selectedBlockID: selectedBlockID,
                selectedOpenSlotID: selectedOpenSlotID,
                onSelectBlock: onSelectBlock,
                onSelectOpenSlot: onSelectOpenSlot
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                ZStack(alignment: .topLeading) {
                    timelineScrollAnchors

                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(perform: onClearSelection)

                            hourGrid

                            ForEach(model.openSlots) { slot in
                                timelineOpenSlot(slot, canvasWidth: geometry.size.width)
                            }

                            ForEach(rootNodes) { node in
                                timelineBlock(node, canvasWidth: geometry.size.width)
                            }

                            ForEach(notes) { note in
                                Button { onSelectNote(note) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label(note.occurredAt.formatted(date: .omitted, time: .shortened), systemImage: "text.bubble")
                                            .font(.caption2.bold())
                                        Text(note.text).font(.caption2).lineLimit(2)
                                    }
                                    .padding(5)
                                    .frame(width: 100, alignment: .leading)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Note, \(note.occurredAt.formatted(date: .omitted, time: .shortened)), \(note.text)")
                                .offset(x: max(0, geometry.size.width - 106), y: scale.yPosition(for: note.occurredAt.minuteOfDay))
                                .zIndex(110)
                            }

                            if let currentMinute {
                                currentTimeLine(minute: currentMinute, canvasWidth: geometry.size.width)
                                    .zIndex(100)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: geometry.size.width, height: canvasHeight, alignment: .topLeading)
                        .animation(timelineAnimation, value: currentMinute)
                    }
                }
                .frame(height: canvasHeight)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                timelineWidth = width
            }
            .task(id: timelineWidth > 0 ? model.date : nil) {
                guard timelineWidth > 0, lastInitialScrollDate != model.date else { return }
                lastInitialScrollDate = model.date

                if let dateNavigationScrollMinute {
                    scroll(
                        to: dateNavigationScrollMinute,
                        anchor: .center,
                        proxy: proxy,
                        animated: false
                    )
                } else if let focusBlockID = model.initialFocusBlockID,
                   let fallbackMinute = currentMinute ?? model.blocks.first(where: { $0.id == focusBlockID })?.startMinuteOfDay {
                    scroll(
                        toBlock: focusBlockID,
                        fallbackMinute: fallbackMinute,
                        anchor: .center,
                        proxy: proxy,
                        animated: false
                    )
                } else if let currentMinute {
                    scroll(to: currentMinute, anchor: .center, proxy: proxy, animated: false)
                } else {
                    scroll(to: model.initialScrollMinute, anchor: .top, proxy: proxy, animated: false)
                }
            }
                .onChange(of: jumpToCurrentTrigger) { _, _ in
                if let selectedBlockID {
                    scroll(
                        toBlock: selectedBlockID,
                        fallbackMinute: currentMinute ?? model.initialScrollMinute,
                        anchor: .center,
                        proxy: proxy,
                        animated: true
                    )
                } else if let currentMinute {
                    scroll(to: currentMinute, anchor: .center, proxy: proxy, animated: true)
                }
                }
                .onChange(of: scrollToBlockTrigger) { _, _ in
                    guard let scrollToBlockID else { return }
                    scroll(
                        toBlock: scrollToBlockID,
                        fallbackMinute: currentMinute ?? model.initialScrollMinute,
                        anchor: .center,
                        proxy: proxy,
                        animated: true
                    )
                }
            }
        }
    }

    private var timelineScrollAnchors: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: scale.topInset)

            ForEach(Array(scrollAnchorMinutes.dropLast().enumerated()), id: \.element) { index, minute in
                let nextMinute = scrollAnchorMinutes[index + 1]
                let segmentHeight = scale.distance(from: minute, to: nextMinute)
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: min(1, segmentHeight))
                        .id(TodayTimelineScrollAnchor(minute: minute))

                    Color.clear
                        .frame(height: max(0, segmentHeight - 1))
                }
            }

            Color.clear
                .frame(height: 1)
                .id(TodayTimelineScrollAnchor(minute: scale.endHour * 60))

            Color.clear
                .frame(height: max(0, scale.bottomInset - 1))
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var hourGrid: some View {
        ForEach(scale.hours, id: \.self) { hour in
            let y = scale.yPosition(for: hour * 60)
            Text(hourLabel(for: hour))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth - 4, alignment: .leading)
                .offset(x: 4, y: y)
        }
    }

    private func currentTimeLine(minute: Int, canvasWidth: CGFloat) -> some View {
        let y = scale.yPosition(for: minute)
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(.red)
                .frame(width: max(0, canvasWidth - labelWidth), height: 2)
                .offset(x: labelWidth)

            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .offset(x: labelWidth - 4)
        }
        .frame(width: canvasWidth, height: 8, alignment: .leading)
        .offset(y: y - 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current time, \(minute.formattedTime)")
        .accessibilityIdentifier("today-current-time-indicator")
    }

    private func timelineBlock(_ node: TodayTimelineNode, canvasWidth: CGFloat) -> some View {
        let startDelta = propagatedStartDelta(
            for: node.block.id,
            timing: timingResolver(node.block.id),
            inheritedStartDelta: 0
        )
        let displayedStartMinuteOfDay = displayedStartMinute(
            for: node.block.id,
            originalStartMinuteOfDay: node.block.startMinuteOfDay,
            startDelta: startDelta
        )
        let displayedEndMinuteOfDay = displayedEndMinute(
            for: node.block.id,
            originalEndMinuteOfDay: node.block.endMinuteOfDay,
            startDelta: startDelta
        )
        let y = scale.yPosition(for: displayedStartMinuteOfDay)
        let blockWidth = max(
            0,
            canvasWidth - labelWidth - trackLeadingInset - trackTrailingInset - (notes.isEmpty ? 0 : 104)
        )

        return TimelineBlockCard(
            node: node,
            scale: scale,
            selectedBlockID: selectedBlockID,
            selectedPathIDs: selectedPathIDs,
            displayedStartMinuteOfDay: displayedStartMinuteOfDay,
            displayedEndMinuteOfDay: displayedEndMinuteOfDay,
            inheritedStartDelta: startDelta,
            timingResolver: timingResolver,
            onSelect: onSelectBlock
        )
        .frame(width: blockWidth, alignment: .leading)
        .offset(x: labelWidth + trackLeadingInset, y: y)
    }

    private func timelineOpenSlot(_ slot: TodayOpenSlotItem, canvasWidth: CGFloat) -> some View {
        let y = scale.yPosition(for: slot.startMinuteOfDay)
        let trackWidth = max(
            0,
            canvasWidth - labelWidth - trackLeadingInset - trackTrailingInset - (notes.isEmpty ? 0 : 104)
        )

        return TimelineOpenSlotEntry(
            slot: slot,
            scale: scale,
            isSelected: selectedOpenSlotID == slot.id,
            onSelect: { onSelectOpenSlot(slot.id) }
        )
        .frame(width: trackWidth, alignment: .leading)
        .offset(x: labelWidth + trackLeadingInset, y: y)
    }

    private var timelineAnimation: Animation? {
        if reduceMotion { return nil }
        return .spring(response: 0.4, dampingFraction: 1)
    }

    private var scrollAnchorMinutes: [Int] {
        var minutes = Set(scale.hours.map { $0 * 60 })
        minutes.insert(scale.startHour * 60)
        minutes.insert(scale.endHour * 60)
        minutes.insert(model.initialScrollMinute)
        model.blocks.forEach {
            minutes.insert($0.startMinuteOfDay)
            minutes.insert($0.endMinuteOfDay)
        }
        model.openSlots.forEach {
            minutes.insert($0.startMinuteOfDay)
            minutes.insert($0.endMinuteOfDay)
        }
        if let currentMinute {
            minutes.insert(currentMinute)
        }
        if let dateNavigationScrollMinute {
            minutes.insert(dateNavigationScrollMinute)
        }
        return minutes
            .filter { $0 >= scale.startHour * 60 && $0 <= scale.endHour * 60 }
            .sorted()
    }

    private var canvasHeight: CGFloat {
        scale.canvasHeight
    }

    private var blocksByID: [UUID: TimelineBlockItem] {
        Dictionary(uniqueKeysWithValues: model.blocks.map { ($0.id, $0) })
    }

    private var rootNodes: [TodayTimelineNode] {
        let childrenByParent = Dictionary(grouping: model.blocks.filter { $0.parentBlockID != nil }) { $0.parentBlockID! }
            .mapValues { $0.sorted(by: timelineNodeSort) }

        func buildNode(for block: TimelineBlockItem) -> TodayTimelineNode {
            TodayTimelineNode(
                block: block,
                children: (childrenByParent[block.id] ?? []).map(buildNode)
            )
        }

        return model.blocks
            .filter { $0.parentBlockID == nil }
            .sorted(by: timelineNodeSort)
            .map(buildNode)
    }

    private var selectedPathIDs: Set<UUID> {
        guard let selectedBlockID else { return [] }

        var path = Set([selectedBlockID])
        var cursor = blocksByID[selectedBlockID]?.parentBlockID

        while let parentID = cursor {
            path.insert(parentID)
            cursor = blocksByID[parentID]?.parentBlockID
        }

        return path
    }

    private func anchorMinute(for minute: Int) -> Int {
        scrollAnchorMinutes.min(by: {
            abs($0 - minute) < abs($1 - minute)
        }) ?? scale.startHour * 60
    }

    private func hourLabel(for hour: Int) -> String {
        if hour == 24 {
            return "24:00"
        }

        return String(format: "%02d:00", hour)
    }

    private func scroll(to minute: Int, anchor: UnitPoint, proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(
                TodayTimelineScrollAnchor(minute: anchorMinute(for: minute)),
                anchor: anchor
            )
        }

        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.3)) {
                action()
            }
        } else {
            action()
        }
    }

    private func scroll(
        toBlock blockID: UUID,
        fallbackMinute: Int,
        anchor: UnitPoint,
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let targetMinute = TodayTimelineScrollTargetResolver.targetMinute(
            for: blockID,
            in: model.blocks,
            fallbackMinute: fallbackMinute
        )
        scroll(to: targetMinute, anchor: anchor, proxy: proxy, animated: animated)
    }

    private func timelineNodeSort(_ lhs: TimelineBlockItem, _ rhs: TimelineBlockItem) -> Bool {
        if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
            return lhs.startMinuteOfDay < rhs.startMinuteOfDay
        }
        if lhs.layerIndex != rhs.layerIndex {
            return lhs.layerIndex < rhs.layerIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private struct TodayTimelineNode: Identifiable {
    let block: TimelineBlockItem
    let children: [TodayTimelineNode]

    var id: UUID { block.id }
}

private func propagatedStartDelta(
    for blockID: UUID,
    timing: TimeBlockTiming?,
    inheritedStartDelta: Int
) -> Int {
    guard inheritedStartDelta != 0 else {
        return 0
    }

    guard case .relative? = timing else {
        return 0
    }

    return inheritedStartDelta
}

private func displayedStartMinute(
    for blockID: UUID,
    originalStartMinuteOfDay: Int,
    startDelta: Int
) -> Int {
    return originalStartMinuteOfDay + startDelta
}

private func displayedEndMinute(
    for blockID: UUID,
    originalEndMinuteOfDay: Int,
    startDelta: Int
) -> Int {
    return originalEndMinuteOfDay + startDelta
}

private struct TimelineBlockCard: View {
    @Environment(\.samoyedTintPreset) private var tintPreset

    let node: TodayTimelineNode
    let scale: TodayTimelineScale
    let selectedBlockID: UUID?
    let selectedPathIDs: Set<UUID>
    let displayedStartMinuteOfDay: Int
    let displayedEndMinuteOfDay: Int
    let inheritedStartDelta: Int
    let timingResolver: (UUID) -> TimeBlockTiming?
    let onSelect: (UUID) -> Void

    private let childLeadingInset: CGFloat = 16
    private let childTrailingInset: CGFloat = 8

    private var block: TimelineBlockItem { node.block }

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: block.layerIndex,
            isBlank: false,
            preset: tintPreset
        )
    }

    private var isSelected: Bool {
        selectedBlockID == block.id
    }

    private var isSelectedAncestor: Bool {
        selectedPathIDs.contains(block.id) && !isSelected
    }

    private var nodeStartDelta: Int {
        propagatedStartDelta(
            for: block.id,
            timing: timingResolver(block.id),
            inheritedStartDelta: inheritedStartDelta
        )
    }

    private var durationHeight: CGFloat {
        scale.distance(from: displayedStartMinuteOfDay, to: displayedEndMinuteOfDay)
    }

    private var outerFrameHeight: CGFloat {
        durationHeight
    }

    private var cardHeight: CGFloat {
        outerFrameHeight
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: max(18, 22 - CGFloat(min(2, block.layerIndex)) * 2),
            style: .continuous
        )
    }

    @ViewBuilder
    private var headerContent: some View {
        if cardHeight >= 60 {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("timeline-title-\(block.id.uuidString)")

                Text(timeRangeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("timeline-time-\(block.id.uuidString)")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        } else {
            HStack(spacing: 8) {
                Text(block.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(timeRangeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
    }

    private var timeRangeText: String {
        "\(displayedStartMinuteOfDay.formattedTime)–\(displayedEndMinuteOfDay.formattedTime)"
    }

    var body: some View {
        GeometryReader { geometry in
            let leadingInset = min(childLeadingInset, max(8, geometry.size.width * 0.12))
            let trailingInset = min(childTrailingInset, max(4, geometry.size.width * 0.06))
            let childWidth = max(geometry.size.width - leadingInset - trailingInset, 1)

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    cardShape
                        .fill(backgroundColor)

                    selectionSurface

                    ForEach(Array(node.children), id: \.id) { child in
                        childCard(
                            for: child,
                            width: childWidth,
                            horizontalInset: leadingInset
                        )
                    }

                    headerContent
                        .zIndex(1)

                }
                .clipShape(cardShape)
                .frame(width: geometry.size.width, height: cardHeight, alignment: .topLeading)
                .overlay(
                    cardShape
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
                .shadow(
                    color: isSelected ? style.accent.opacity(0.16) : .clear,
                    radius: 10,
                    y: 4
                )
            }
        }
        .frame(height: outerFrameHeight)
        .id(block.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows block details")
        .accessibilityAddTraits(.isButton)
        .accessibilitySortPriority(Double(24 * 60 - displayedStartMinuteOfDay))
        .accessibilityAction {
            onSelect(block.id)
        }
    }

    private var accessibilityLabel: String {
        [
            block.title,
            "\(displayedStartMinuteOfDay.formattedTime) to \(displayedEndMinuteOfDay.formattedTime)"
        ]
        .joined(separator: ", ")
    }

    private var backgroundColor: Color {
        if isSelected {
            return style.strongSurface
        }

        if isSelectedAncestor {
            return style.surface.opacity(0.94)
        }

        return style.surface
    }

    private var borderColor: Color {
        if isSelected {
            return style.accent
        }

        if isSelectedAncestor {
            return style.accent.opacity(0.42)
        }

        return Color(uiColor: .separator)
    }

    private var borderWidth: CGFloat {
        if isSelected {
            return 2.2
        }

        if isSelectedAncestor {
            return 1.5
        }

        return 1
    }

    private func childYOffset(for child: TodayTimelineNode) -> CGFloat {
        let childRange = childDisplayedRange(of: child)
        return scale.distance(
            from: displayedStartMinuteOfDay,
            to: childRange.startMinuteOfDay
        )
    }

    private func childCard(
        for child: TodayTimelineNode,
        width: CGFloat,
        horizontalInset: CGFloat
    ) -> some View {
        let childRange = childDisplayedRange(of: child)

        return TimelineBlockCard(
            node: child,
            scale: scale,
            selectedBlockID: selectedBlockID,
            selectedPathIDs: selectedPathIDs,
            displayedStartMinuteOfDay: childRange.startMinuteOfDay,
            displayedEndMinuteOfDay: childRange.endMinuteOfDay,
            inheritedStartDelta: nodeStartDelta,
            timingResolver: timingResolver,
            onSelect: onSelect
        )
        .frame(width: width)
        .offset(
            x: horizontalInset,
            y: childYOffset(for: child)
        )
    }

    private func childDisplayedRange(of child: TodayTimelineNode) -> (startMinuteOfDay: Int, endMinuteOfDay: Int) {
        let startDelta = propagatedStartDelta(
            for: child.block.id,
            timing: timingResolver(child.block.id),
            inheritedStartDelta: nodeStartDelta
        )

        return (
            startMinuteOfDay: displayedStartMinute(
                for: child.block.id,
                originalStartMinuteOfDay: child.block.startMinuteOfDay,
                startDelta: startDelta
            ),
            endMinuteOfDay: displayedEndMinute(
                for: child.block.id,
                originalEndMinuteOfDay: child.block.endMinuteOfDay,
                startDelta: startDelta
            )
        )
    }

    private var selectionSurface: some View {
        Color.clear
            .contentShape(cardShape)
            .onTapGesture {
                onSelect(block.id)
            }
    }

}

private struct TimelineOpenSlotEntry: View {
    @Environment(\.samoyedTintPreset) private var tintPreset

    let slot: TodayOpenSlotItem
    let scale: TodayTimelineScale
    let isSelected: Bool
    let onSelect: () -> Void

    private var slotHeight: CGFloat {
        scale.distance(from: slot.startMinuteOfDay, to: slot.endMinuteOfDay)
    }

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: 0,
            isBlank: true,
            preset: tintPreset
        )
    }

    private var timeRangeText: String {
        "\(slot.startMinuteOfDay.formattedTime)–\(slot.endMinuteOfDay.formattedTime)"
    }

    private var accessibilityText: String {
        "Open Time, \(slot.startMinuteOfDay.formattedTime) to \(slot.endMinuteOfDay.formattedTime)"
    }

    var body: some View {
        slotShape
            .fill(
                isSelected
                    ? style.strongSurface
                    : Color(uiColor: .systemGroupedBackground)
            )
            .overlay(slotBorder)
            .frame(height: slotHeight)
            .overlay(alignment: .topLeading) { slotLabel }
            .contentShape(slotShape)
            .onTapGesture(perform: onSelect)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Shows open time details")
            .accessibilityAddTraits(.isButton)
            .accessibilitySortPriority(Double(24 * 60 - slot.startMinuteOfDay))
            .accessibilityAction {
                onSelect()
            }
    }

    private var slotShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var slotBorder: some View {
        slotShape.strokeBorder(
            isSelected ? style.accent : Color(uiColor: .separator),
            lineWidth: isSelected ? 2 : 1
        )
    }

    private var slotLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Open Time")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(timeRangeText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

private struct TodayBlockInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SamoyedStore.self) private var store
    @State private var feedbackContext: FeedbackSheetContext?
    @State private var completionFeedbackTrigger = 0

    let date: LocalDay
    let detail: BlockDetailModel
    let onSelectParent: () -> Void
    let onToggleTask: (UUID) -> Void

    var body: some View {
        Form {
            Section {
                header
            }

            if currentDetail.parentBlockTitle != nil {
                Section {
                    parentButton
                }
            }

            Section("Note") {
                if let note = currentDetail.note, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No note")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Checklist") {
                if currentDetail.tasks.isEmpty {
                    Text("No checklist items")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(currentDetail.tasks) { task in
                        Button {
                            onToggleTask(task.id)
                            if !task.isCompleted {
                                completionFeedbackTrigger += 1
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.accentColor)
                                    .font(.title3)

                                Text(task.title)
                                    .strikethrough(task.isCompleted, color: .secondary)
                                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(task.title)
                        .accessibilityValue(task.isCompleted ? "Completed" : "Not completed")
                        .accessibilityHint("Toggles this checklist item")
                    }
                }
            }

            Section("Reminders") {
                if currentDetail.reminders.isEmpty {
                    Text("No reminders")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(currentDetail.reminders) { reminder in
                            Label(reminderSummary(reminder), systemImage: "bell.badge")
                                .font(.body)
                        }
                    }
                }
            }

            Section {
                Button {
                    feedbackContext = FeedbackSheetContext(
                        target: .block(blockID: currentDetail.id),
                        targetTitle: currentDetail.title,
                        targetDetail: "\(currentDetail.startMinuteOfDay.formattedTime) to \(currentDetail.endMinuteOfDay.formattedTime)",
                        localDay: date,
                        source: .blockDetails
                    )
                } label: {
                    Label("Give Feedback on This Block", systemImage: "bubble.left")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("block-details-feedback")
            }
        }
        .navigationTitle("Block Details")
        .navigationBarTitleDisplayMode(.inline)
        .presentationDetents([.fraction(0.68), .large])
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .accessibilityIdentifier("block-details-done")
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

    private var currentDetail: BlockDetailModel {
        (try? store.blockDetailModel(on: date, blockID: detail.id)) ?? detail
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(currentDetail.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("\(currentDetail.startMinuteOfDay.formattedTime) - \(currentDetail.endMinuteOfDay.formattedTime)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var parentButton: some View {
        Button(action: onSelectParent) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.up.left")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Parent Block")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(currentDetail.parentBlockTitle ?? "")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Parent block, \(currentDetail.parentBlockTitle ?? "")")
    }

    private func reminderSummary(_ reminder: ReminderRule) -> String {
        if let preset = ReminderPreset(rule: reminder) {
            return preset.title
        }

        switch reminder.triggerMode {
        case .atStart:
            return "At start"
        case .beforeStart:
            return "\(reminder.offsetMinutes) min before"
        }
    }
}

private struct TodayOpenSlotInspectorView: View {
    @Environment(\.dismiss) private var dismiss

    let slot: TodayOpenSlotItem

    var body: some View {
        Form {
            Section {
                LabeledContent("Time", value: "\(slot.startMinuteOfDay.formattedTime) - \(slot.endMinuteOfDay.formattedTime)")
                LabeledContent("Duration", value: durationText)
            }

            Section {
                Text("This gap is free in the selected routine projection.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Open Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var durationText: String {
        let hours = slot.durationMinutes / 60
        let minutes = slot.durationMinutes % 60

        switch (hours, minutes) {
        case (0, let minutes):
            return "\(minutes) min available"
        case (let hours, 0):
            return hours == 1 ? "1 hour available" : "\(hours) hours available"
        default:
            return "\(hours)h \(minutes)m available"
        }
    }
}

private struct TodayUnavailableInspectorView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int

    var body: some View {
        Form {
            Section {
                Text(title)
                    .font(.headline)

                Text("\(startMinuteOfDay.formattedTime) - \(endMinuteOfDay.formattedTime)")
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("This block is no longer available in the current day plan.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Unavailable Block")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

#Preview("Today Root") {
    TodayRootView()
        .environment(PreviewSupport.store(tab: .today))
}

#Preview("Today Root - Empty Day") {
    TodayRootView()
        .environment(
            PreviewSupport.store(
                tab: .today,
                document: SamoyedDocument()
            )
        )
}

#Preview("Today Root - Loading") {
    TodayRootView()
        .environment(PreviewSupport.store(tab: .today, loaded: false))
}

#Preview("Today Timeline") {
    let model = PreviewSupport.todayModel()
    TodayTimelineView(
        model: model,
        notes: [],
        onSelectNote: { _ in },
        selectedBlockID: model.selectedBlock?.id,
        selectedOpenSlotID: nil,
        currentMinute: 9 * 60 + 30,
        dateNavigationScrollMinute: nil,
        jumpToCurrentTrigger: 0,
        scrollToBlockID: nil,
        scrollToBlockTrigger: 0,
        timingResolver: { _ in nil },
        onSelectBlock: { _ in },
        onSelectOpenSlot: { _ in },
        onClearSelection: {}
    )
}

#Preview("Today Timeline - Blank") {
    let model = PreviewSupport.todayModel(document: SamoyedDocument(), currentMinute: nil)
    TodayTimelineView(
        model: model,
        notes: [],
        onSelectNote: { _ in },
        selectedBlockID: nil,
        selectedOpenSlotID: nil,
        currentMinute: nil,
        dateNavigationScrollMinute: nil,
        jumpToCurrentTrigger: 0,
        scrollToBlockID: nil,
        scrollToBlockTrigger: 0,
        timingResolver: { _ in nil },
        onSelectBlock: { _ in },
        onSelectOpenSlot: { _ in },
        onClearSelection: {}
    )
}

#Preview("Today Timeline - Historical Day") {
    let day = PreviewSupport.referenceDay.adding(days: -1)
    let document = PreviewSupport.seededDocument(on: day)
    let model = try! SamoyedPresentation.todayScreenModel(
        document: document,
        date: day,
        selectedBlockID: nil,
        currentMinute: nil
    )
    TodayTimelineView(
        model: model,
        notes: [],
        onSelectNote: { _ in },
        selectedBlockID: model.selectedBlock?.id,
        selectedOpenSlotID: nil,
        currentMinute: nil,
        dateNavigationScrollMinute: nil,
        jumpToCurrentTrigger: 0,
        scrollToBlockID: nil,
        scrollToBlockTrigger: 0,
        timingResolver: { _ in nil },
        onSelectBlock: { _ in },
        onSelectOpenSlot: { _ in },
        onClearSelection: {}
    )
}
