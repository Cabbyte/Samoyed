import SwiftUI

struct RoutinesRootView: View {
    @Environment(SamoyedStore.self) private var store
    @State private var pendingTodayChoice: UUID?

    var body: some View {
        RootScreenContainer(
            isLoaded: store.isLoaded,
            loadingTitle: "Loading Routines",
            loadingSystemImage: "square.stack.3d.up",
            loadingDescription: "Preparing your local routine library.",
            errorTitle: "Unable to Load Routines",
            retry: store.reload,
            load: { try store.templatesScreenModel() }
        ) { model in
            List {
                currentSection(model)
                availableSection(model)
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("All Routines")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Switch today’s routine?",
            isPresented: Binding(
                get: { pendingTodayChoice != nil },
                set: { if !$0 { pendingTodayChoice = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Switch Routine") {
                guard let pendingTodayChoice else { return }
                chooseForToday(templateID: pendingTodayChoice, forceReplace: true)
            }
            Button("Keep Current Routine", role: .cancel) {
                pendingTodayChoice = nil
            }
        } message: {
            Text("Today already has execution progress. Confirming replaces only today’s materialized plan.")
        }
    }

    @ViewBuilder
    private func currentSection(_ model: TemplatesScreenModel) -> some View {
        if let current = model.todayChooser.currentSelection {
            Section("Current") {
                NavigationLink {
                    RoutineDetailView(routineID: current.id)
                } label: {
                    RoutineListRow(
                        routine: current,
                        subtitle: "Running today",
                        isSelected: true
                    )
                }
                .accessibilityIdentifier("routine-current")
            }
        }
    }

    private func availableSection(_ model: TemplatesScreenModel) -> some View {
        Section {
            let available = model.savedTemplates.filter { !$0.isCurrentForToday }
            if available.isEmpty {
                ContentUnavailableView {
                    Label("No Other Routines", systemImage: "square.stack.3d.up.slash")
                } description: {
                    Text("Import a Routine Config File or create one with ChatGPT.")
                } actions: {
                    Button("Import Routine File") {
                        store.openLibrary(destination: .routineFiles)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(available) { routine in
                    NavigationLink {
                        RoutineDetailView(routineID: routine.id)
                    } label: {
                        RoutineListRow(
                            routine: routine,
                            subtitle: routine.timeRangeText ?? "Available routine",
                            isSelected: false
                        )
                    }
                    .accessibilityIdentifier("routine-available-\(routine.id.uuidString)")
                }
            }
        } header: {
            Text("Available")
        } footer: {
            Text("Routine structure is read-only on iPhone. Import an updated file or review improvements from Suggestions.")
        }
    }

    private func chooseForToday(templateID: UUID, forceReplace: Bool) {
        do {
            switch try store.chooseTemplate(
                for: .today(),
                templateID: templateID,
                source: .pickedTemplate,
                forceReplace: forceReplace
            ) {
            case .applied:
                pendingTodayChoice = nil
            case .requiresConfirmation:
                pendingTodayChoice = templateID
            }
        } catch {
            store.presentError(error)
        }
    }
}

private struct RoutineListRow: View {
    let routine: TemplateCandidateSummary
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.tint)
                .frame(width: 28, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.title)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Current routine")
            }
        }
        .contentShape(Rectangle())
    }
}

struct RoutineDetailView: View {
    @Environment(\.openURL) private var openURL
    @Environment(SamoyedStore.self) private var store
    @State private var renderedBlocks: [TimeBlock] = []
    @State private var isConfirmingReplacement = false

    let routineID: UUID

    private var routine: SavedDayTemplate? {
        store.savedTemplate(id: routineID)
    }

    private var isCurrentForToday: Bool {
        store.document.daySelection(for: .today())?.selectedTemplateID == routineID
            || store.document.dayPlan(for: .today())?.sourceSavedTemplateID == routineID
    }

    private var timeRangeText: String {
        guard
            let start = renderedBlocks.compactMap(\.resolvedStartMinuteOfDay).min(),
            let end = renderedBlocks.compactMap(\.resolvedEndMinuteOfDay).max()
        else { return "No schedule" }
        return "\(start.formattedTime)–\(end.formattedTime)"
    }

    var body: some View {
        Group {
            if let routine {
                List {
                    Section("Overview") {
                        LabeledContent("Status", value: isCurrentForToday ? "Running today" : "Available")
                        LabeledContent("Time", value: timeRangeText)
                        LabeledContent("Blocks", value: "\(renderedBlocks.count)")
                        LabeledContent("Version", value: "\(routine.revision)")
                    }

                    Section("Routine Structure") {
                        ForEach(renderedBlocks) { block in
                            RoutineStructureRow(block: block)
                        }
                    }

                    Section {
                        Button {
                            selectForToday(forceReplace: false)
                        } label: {
                            Label(
                                isCurrentForToday ? "Selected for Today" : "Select for Today",
                                systemImage: isCurrentForToday ? "checkmark.circle.fill" : "calendar.badge.checkmark"
                            )
                        }
                        .disabled(isCurrentForToday)
                        .accessibilityIdentifier("routine-select-today")

                        Button {
                            if let url = URL(string: "https://chatgpt.com/?q=Help%20me%20improve%20my%20Samoyed%20routine") {
                                openURL(url)
                            }
                        } label: {
                            Label("Ask Planner to Improve", systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("routine-ask-planner")
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(routine.title)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView(
                    "Routine Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This routine may have been removed or replaced.")
                )
            }
        }
        .confirmationDialog("Replace today’s routine?", isPresented: $isConfirmingReplacement) {
            Button("Replace Routine") { selectForToday(forceReplace: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Today already has execution progress. This replaces only today’s plan.")
        }
        .task(id: routine?.updatedAt) { refreshPreview() }
    }

    private func selectForToday(forceReplace: Bool) {
        do {
            switch try store.chooseTemplate(
                for: .today(),
                templateID: routineID,
                source: .pickedTemplate,
                forceReplace: forceReplace
            ) {
            case .applied: isConfirmingReplacement = false
            case .requiresConfirmation: isConfirmingReplacement = true
            }
        } catch {
            store.presentError(error)
        }
    }

    private func refreshPreview() {
        guard let routine, let preview = try? TemplateEngine.previewDayPlan(from: routine) else {
            renderedBlocks = []
            return
        }
        renderedBlocks = preview.blocks
            .filter { !$0.isCancelled && !$0.isBlankBaseBlock }
            .sorted {
                if $0.layerIndex != $1.layerIndex { return $0.layerIndex < $1.layerIndex }
                return ($0.resolvedStartMinuteOfDay ?? 0) < ($1.resolvedStartMinuteOfDay ?? 0)
            }
    }
}

private struct RoutineStructureRow: View {
    let block: TimeBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Image(systemName: block.layerIndex == 0 ? "rectangle" : "arrow.turn.down.right")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(block.title)
                    .font(.body.weight(.semibold))
                Spacer()
                if let start = block.resolvedStartMinuteOfDay, let end = block.resolvedEndMinuteOfDay {
                    Text("\(start.formattedTime)–\(end.formattedTime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let note = block.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, CGFloat(block.layerIndex) * 16)
        .accessibilityElement(children: .combine)
    }
}

struct UsualWeekView: View {
    @Environment(SamoyedStore.self) private var store

    var body: some View {
        List {
            if store.savedTemplates.isEmpty {
                ContentUnavailableView {
                    Label("No Routines", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Import a Routine Config File before assigning your usual week.")
                } actions: {
                    Button("Import Routine File") {
                        store.openLibrary(destination: .routineFiles)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                Section {
                    ForEach(Weekday.allCases, id: \.self) { weekday in
                        Menu {
                            Button("No Routine") {
                                assign(nil, to: weekday)
                            }
                            ForEach(store.savedTemplates) { routine in
                                Button(routine.title) {
                                    assign(routine.id, to: weekday)
                                }
                            }
                        } label: {
                            LabeledContent(weekdayTitle(weekday)) {
                                HStack(spacing: 6) {
                                    Text(assignedTitle(for: weekday))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("usual-week-\(weekday.rawValue)")
                    }
                } footer: {
                    Text("Changes affect future defaults only. Today’s running plan stays unchanged.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Usual Week")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func assign(_ routineID: UUID?, to weekday: Weekday) {
        do {
            try store.assignRoutine(routineID, to: weekday)
        } catch {
            store.presentError(error)
        }
    }

    private func assignedTitle(for weekday: Weekday) -> String {
        guard let id = store.assignedTemplateID(for: weekday) else { return "No Routine" }
        return store.savedTemplate(id: id)?.title ?? "Needs Reassignment"
    }

    private func weekdayTitle(_ weekday: Weekday) -> String {
        Calendar.current.weekdaySymbols[(weekday.rawValue - 1 + 7) % 7]
    }
}

#Preview("Routines") {
    NavigationStack { RoutinesRootView() }
        .environment(PreviewSupport.store(tab: .library))
}
