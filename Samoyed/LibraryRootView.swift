import SwiftUI

enum LibraryDestination: Hashable {
    case routines
    case appearance
    case routineFiles
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
                    NavigationLink {
                        RoutineEditorView(mode: .create)
                    } label: {
                        Label("New Routine", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .routines:
                    RoutinesRootView()
                case .appearance:
                    LibraryAppearanceView()
                case .routineFiles:
                    LibraryImportExportView()
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
                NavigationLink { NestAccountView() } label: {
                    Label("Samoyed Nest · \(store.nest.status)", systemImage: "person.crop.circle")
                }
            }
            Section {
                Text("Choose, preview, and reuse routines.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            }

            if model.savedTemplates.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Routines", systemImage: "square.and.arrow.down")
                    } description: {
                        Text("Create a reusable routine or import a Routine Config File.")
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
                routinesSection
                toolsSection
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var todaySection: some View {
        Section("Today") {
            if let current = model.todayChooser.currentSelection {
                NavigationLink {
                    RoutineDetailView(routineID: current.id)
                } label: {
                    LibraryRoutineRow(
                        routine: current,
                        subtitle: "Running",
                        showsSelection: true
                    )
                }
            } else {
                NavigationLink(value: LibraryDestination.routines) {
                    Label("Choose Today’s Routine", systemImage: "calendar.badge.exclamationmark")
                }
            }
        }
    }

    @ViewBuilder
    private var routinesSection: some View {
        Section("Routines") {
            ForEach(model.savedTemplates.filter { !$0.isCurrentForToday }.prefix(3)) { routine in
                NavigationLink {
                    RoutineDetailView(routineID: routine.id)
                } label: {
                    LibraryRoutineRow(
                        routine: routine,
                        subtitle: routine.timeRangeText ?? "Reusable routine",
                        showsSelection: false
                    )
                }
            }

            NavigationLink(value: LibraryDestination.routines) {
                Label("All Routines", systemImage: "square.stack.3d.up")
            }
        }
    }

    @ViewBuilder
    private var toolsSection: some View {
        Section("Library Tools") {
            NavigationLink(value: LibraryDestination.appearance) {
                Label("Appearance", systemImage: "paintpalette")
            }

            NavigationLink(value: LibraryDestination.routineFiles) {
                Label("Routine Files", systemImage: "arrow.up.arrow.down")
            }
        }
    }
}

private struct LibraryRoutineRow: View {
    let routine: TemplateCandidateSummary
    let subtitle: String
    let showsSelection: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.title)
                    .font(.body)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsSelection {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected for today")
            }
        }
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
