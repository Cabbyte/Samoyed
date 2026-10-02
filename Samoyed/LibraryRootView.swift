import SwiftUI

enum LibraryDestination: Hashable {
    case routines
    case usualWeek
    case suggestions
    case planner
    case appearance
    case routineFiles
    case nest
}

struct LibraryRootView: View {
    @Environment(SamoyedStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationStack(path: $store.libraryNavigationPath) {
            Group {
                if !store.isLoaded {
                    ScreenLoadingView(
                        title: "Loading Routines",
                        systemImage: "square.stack.3d.up",
                        description: "Preparing today’s routine choice and your local routine library."
                    )
                } else {
                    RootScreenContainer(
                        isLoaded: true,
                        loadingTitle: "Loading Routines",
                        loadingSystemImage: "square.stack.3d.up",
                        loadingDescription: "Preparing today’s routine choice and your local routine library.",
                        errorTitle: "Unable to Load Library",
                        retry: store.reload,
                        load: { try store.templatesScreenModel() }
                    ) { model in
                        LibraryContent(model: model)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let conflicts = try? store.noteConflicts(), !conflicts.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { NestNoteConflictsView() } label: {
                            Label("Sync conflicts", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: LibraryDestination.routineFiles) {
                        Label("Add Routine", systemImage: "plus")
                    }
                    .accessibilityIdentifier("library-add-routine")
                }
            }
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .routines:
                    RoutinesRootView()
                case .usualWeek:
                    UsualWeekView()
                case .suggestions:
                    SuggestionsInboxView()
                case .planner:
                    PlannerView()
                case .appearance:
                    LibraryAppearanceView()
                case .routineFiles:
                    LibraryImportExportView()
                case .nest:
                    NestAccountView()
                }
            }
        }
    }
}

private struct LibraryContent: View {
    @Environment(SamoyedStore.self) private var store

    let model: TemplatesScreenModel

    var body: some View {
        List {
            Section {
                Button {
                    store.libraryNavigationPath.append(.nest)
                } label: {
                    HStack(spacing: 8) {
                        NestSyncSummary(nest: store.nest)
                        Image("NestChevron")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library-nest")
            }

            if model.savedTemplates.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Routines", systemImage: "square.and.arrow.down")
                    } description: {
                        Text("Import a Routine Config File or create one with ChatGPT.")
                    } actions: {
                        Button {
                            store.libraryNavigationPath.append(.routineFiles)
                        } label: {
                            Label("Import Routine Config File", systemImage: "square.and.arrow.down")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                }
                .listRowBackground(Color.clear)
            } else {
                todaySection
                suggestionsSection
                routinesSection
            }
            toolsSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(20)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .environment(\.defaultMinListRowHeight, 48)
    }

    @ViewBuilder
    private var todaySection: some View {
        Section {
            if let current = model.todayChooser.currentSelection {
                NavigationLink {
                    RoutineDetailView(routineID: current.id)
                } label: {
                    LibrarySummaryRow(
                        title: current.title,
                        subtitle: "Running",
                        status: "RUNNING",
                        systemImage: "square.stack.3d.up"
                    )
                }
                .accessibilityIdentifier("library-current-routine")
            } else {
                NavigationLink(value: LibraryDestination.routines) {
                    Label("Choose Today’s Routine", systemImage: "calendar.badge.exclamationmark")
                }
            }
        } header: { sectionTitle("Today") }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        let pending = store.document.suggestions.filter { $0.lifecycleState == .pending }
        let changeCount = pending.reduce(0) { $0 + $1.changes.count }
        if !pending.isEmpty {
            Section("Suggestions") {
                NavigationLink(value: LibraryDestination.suggestions) {
                    LibrarySummaryRow(
                        title: pending.contains(where: { $0.kind == .dailyPlan })
                            ? "Tomorrow’s Plan" : "Routine Improvements",
                        subtitle: changeCount == 0 ? "Ready to review"
                            : "\(changeCount) changes · Ready to review",
                        status: "READY"
                    )
                }
                .accessibilityIdentifier("library-suggestions")
            }
        }
    }

    @ViewBuilder
    private var routinesSection: some View {
        Section {
            ForEach(model.savedTemplates.prefix(2)) { routine in
                NavigationLink {
                    RoutineDetailView(routineID: routine.id)
                } label: {
                    LibrarySummaryRow(
                        title: routine.title,
                        subtitle: routine.timeRangeText ?? "No scheduled blocks",
                        systemImage: "square.stack.3d.up"
                    )
                }
            }
            NavigationLink(value: LibraryDestination.routines) {
                Label("All Routines", systemImage: "square.stack.3d.up")
            }
        } header: { sectionTitle("Routines") }
    }

    private var toolsSection: some View {
        Section {
            NavigationLink(value: LibraryDestination.appearance) {
                Label { Text("Appearance") } icon: { Image("LibraryPalette") }
            }
            .accessibilityIdentifier("library-appearance")
            NavigationLink(value: LibraryDestination.routineFiles) {
                Label { Text("Routine Files") } icon: { Image("LibraryFiles") }
            }
            NavigationLink(value: LibraryDestination.usualWeek) {
                LibrarySummaryRow(title: "Usual Week", subtitle: usualWeekSummary, systemImage: "calendar")
            }
            NavigationLink(value: LibraryDestination.planner) {
                LibrarySummaryRow(title: "Planner", subtitle: plannerStatusText, systemImage: "sparkles")
            }
            .accessibilityIdentifier("library-planner")
        } header: { sectionTitle("Library Tools") }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline).foregroundStyle(Color(uiColor: .secondaryLabel)).textCase(nil)
    }

    private var plannerStatusText: String {
        switch store.document.plannerSettings.connectionState {
        case .disconnected: "Not Connected"
        case .connected: "Connected"
        case .unavailable: "Unavailable · routines continue locally"
        case .needsAttention: "Needs Attention"
        }
    }

    private var usualWeekSummary: String {
        let count = Set(model.savedTemplates.flatMap(\.assignedWeekdays)).count
        switch count {
        case 0: return "No default routines"
        case 7: return "Configured · Mon–Sun"
        default: return "Configured · \(count) of 7 days"
        }
    }
}

private struct LibrarySummaryRow: View {
    let title: String
    let subtitle: String
    var status: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if status == "RUNNING" {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            } else if let status {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status == "READY" ? Color.orange : Color.secondary)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([subtitle, status].compactMap { $0 }.joined(separator: ", "))
    }
}

struct LibraryAppearanceView: View {
    @Environment(SamoyedStore.self) private var store

    var body: some View {
        List {
            Section("Tint Presets") {
                ForEach(AppTintPreset.allCases) { preset in
                    Button {
                        store.applyTintPreset(preset)
                    } label: {
                        TintPresetRow(
                            preset: preset,
                            isSelected: store.tintPreset == preset
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appearance-\(preset.rawValue)")
                    .accessibilityAddTraits(store.tintPreset == preset ? [.isSelected] : [])
                }
            }

            Section {
                LabeledContent("Global Accent", value: store.tintPreset.title)
                LabeledContent("Blank Blocks", value: "Neutral")
            } header: {
                Text("Behavior")
            } footer: {
                Text("The selected tint updates Now, Today, Library, widgets, and Live Activities while blank blocks remain neutral.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TintPresetRow: View {
    let preset: AppTintPreset
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            TintPresetSwatch(preset: preset)

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(preset.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct TintPresetSwatch: View {
    let preset: AppTintPreset

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .leading) {
                ForEach(Array((0 ..< 4).reversed()), id: \.self) { layer in
                    let style = LayerVisualStyle.forBlock(
                        layerIndex: layer,
                        isBlank: false,
                        preset: preset
                    )

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(style.strongSurface)
                        .frame(width: 30, height: 21)
                        .offset(x: CGFloat(layer) * 7)
                }
            }
            .frame(width: 55, height: 25, alignment: .leading)

            Circle()
                .fill(preset.tintColor)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                }
        }
        .frame(width: 62, height: 34)
        .accessibilityHidden(true)
    }
}

#Preview("Library") {
    LibraryRootView()
        .environment(PreviewSupport.store(tab: .library))
}

#Preview("Appearance") {
    NavigationStack {
        LibraryAppearanceView()
    }
    .environment(PreviewSupport.store(tab: .library, tintPreset: .ocean))
}
