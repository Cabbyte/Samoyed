import SwiftUI
import UserNotifications

struct ActivationRootView: View {
    @Environment(\.openURL) private var openURL
    @Environment(SamoyedStore.self) private var store
    @State private var step: ActivationStep = .choose
    @State private var selectedWeekdays: Set<Weekday> = [
        .monday, .tuesday, .wednesday, .thursday, .friday
    ]
    @State private var notificationsRequested = false
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .choose:
                    choiceList
                case .starterReady:
                    starterReadyList
                }
            }
            .navigationTitle(step == .choose ? "Set Up Samoyed" : "Starter Routine Ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step == .starterReady {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { step = .choose }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(step == .choose ? "Step 1 of 2" : "Step 2 of 2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(store.tintPreset.tintColor)
        .environment(\.samoyedTintPreset, store.tintPreset)
        .accessibilityIdentifier("first-run")
    }

    private var choiceList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "bolt.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Choose how to begin")
                        .font(.title2.bold())
                    Text("Samoyed runs approved routines locally. Routine structure stays read-only on iPhone.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                Button {
                    step = .starterReady
                } label: {
                    ActivationChoiceRow(
                        title: "Use a Starter Routine",
                        subtitle: "Install a calm Workday for Monday through Friday.",
                        systemImage: "checklist"
                    )
                }
                .accessibilityIdentifier("activation-starter")

                Button {
                    if let url = URL(string: "https://chatgpt.com/?q=Create%20a%20Samoyed%20Routine%20Config") {
                        openURL(url)
                    }
                } label: {
                    ActivationChoiceRow(
                        title: "Create with ChatGPT",
                        subtitle: "Design a Routine Config outside the app, then import it.",
                        systemImage: "sparkles"
                    )
                }
                .accessibilityIdentifier("activation-chatgpt")

                NavigationLink {
                    LibraryImportExportView()
                } label: {
                    ActivationChoiceRow(
                        title: "Import Routine File",
                        subtitle: "Open an existing YAML Routine Config File.",
                        systemImage: "square.and.arrow.down"
                    )
                }
                .accessibilityIdentifier("activation-import")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var starterReadyList: some View {
        List {
            Section {
                Label("Workday is ready", systemImage: "checkmark.seal.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text("Morning, Focus, Lunch, Afternoon, and Evening blocks are installed as a read-only structure.")
                    .foregroundStyle(.secondary)
            }

            Section("Weekdays") {
                ForEach(Weekday.allCases, id: \.self) { weekday in
                    Toggle(weekdayTitle(weekday), isOn: weekdayBinding(weekday))
                        .frame(minHeight: 44)
                }
                if selectedWeekdays.isEmpty {
                    Label("Choose at least one weekday.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Preferences") {
                Toggle("Notifications", isOn: $notificationsRequested)
                    .frame(minHeight: 44)
                LabeledContent("Planner", value: "Not Connected")
            }

            Section {
                Button {
                    startUsingSamoyed()
                } label: {
                    HStack {
                        Spacer()
                        if isStarting { ProgressView() }
                        Text("Start Using Samoyed")
                            .font(.headline)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
                .disabled(selectedWeekdays.isEmpty || isStarting)
                .accessibilityIdentifier("activation-start")
            } footer: {
                Text("Planner remains optional. The starter routine works offline.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func startUsingSamoyed() {
        isStarting = true
        Task {
            if notificationsRequested {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
            }
            await MainActor.run {
                defer { isStarting = false }
                do {
                    try store.activateStarterRoutine(assignedWeekdays: selectedWeekdays)
                } catch {
                    store.presentError(error)
                }
            }
        }
    }

    private func weekdayBinding(_ weekday: Weekday) -> Binding<Bool> {
        Binding(
            get: { selectedWeekdays.contains(weekday) },
            set: { isOn in
                if isOn { selectedWeekdays.insert(weekday) }
                else { selectedWeekdays.remove(weekday) }
            }
        )
    }

    private func weekdayTitle(_ weekday: Weekday) -> String {
        Calendar.current.weekdaySymbols[(weekday.rawValue - 1 + 7) % 7]
    }
}

private enum ActivationStep {
    case choose
    case starterReady
}

private struct ActivationChoiceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview("First Run") {
    ActivationRootView()
        .environment(
            SamoyedStore(
                documentRepository: SamoyedDocumentRepository(
                    fileURL: FileManager.default.temporaryDirectory
                        .appending(path: "samoyed-first-run-preview.json")
                )
            )
        )
}
