import SwiftUI

struct ActivationRootView: View {
    @Environment(SamoyedStore.self) private var store
    @State private var draft = SimpleDayTypeDraft.workdayStarter
    @State private var startedAt = Date.now
    @State private var errorMessage: String?
    @State private var didRecordStart = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { NestAccountView() } label: { Label("Connect Samoyed Nest", systemImage: "person.crop.circle") }
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Make today run itself")
                            .font(.title.bold())
                        Text("Start with one Workday. You can change every detail now and adjust only today later.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                SimpleDayTypeFormSections(draft: $draft)

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip for now") { store.continueWithoutRoutine() }
                }
            }
            .navigationTitle("Set Up Samoyed")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: activate) {
                    Text("Start Today")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(validationMessage != nil)
                .accessibilityIdentifier("activation-start")
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
                .accessibilityHint("Creates this day type and opens Now")
            }
        }
        .tint(store.tintPreset.tintColor)
        .environment(\.samoyedTintPreset, store.tintPreset)
        .onAppear {
            guard !didRecordStart else { return }
            didRecordStart = true
            startedAt = .now
            store.recordValidationEvent(.activationStarted, outcome: "shown", at: startedAt)
        }
    }

    private var validationMessage: String? {
        guard !draft.assignedWeekdays.isEmpty else {
            return SamoyedCoreError.emptyActivationWeekdays.localizedDescription
        }
        do {
            _ = try draft.makeNewTemplate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func activate() {
        do {
            try store.activate(with: draft, startedAt: startedAt)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SimpleDayTypeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SamoyedStore.self) private var store
    @State private var draft: SimpleDayTypeDraft
    @State private var errorMessage: String?
    @State private var startedAt = Date.now

    init(draft: SimpleDayTypeDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                SimpleDayTypeFormSections(draft: $draft)
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(draft.templateID == nil ? "New Day Type" : "Edit Day Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recordCompletion(outcome: "cancelled")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(validationMessage != nil)
                }
            }
        }
        .interactiveDismissDisabled(false)
        .onAppear {
            startedAt = .now
            store.recordValidationEvent(
                .dayTypeEditOpened,
                outcome: "opened",
                variant: draft.templateID == nil ? "new" : "edit",
                at: startedAt
            )
        }
    }

    private var validationMessage: String? {
        do {
            _ = try draft.makeNewTemplate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func save() {
        do {
            try store.saveSimpleDayType(draft)
            recordCompletion(outcome: "saved")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordCompletion(outcome: String) {
        store.recordValidationEvent(
            .dayTypeEditCompleted,
            outcome: outcome,
            variant: draft.templateID == nil ? "new" : "edit",
            durationMilliseconds: Int(Date.now.timeIntervalSince(startedAt) * 1_000)
        )
    }
}

struct SimpleDayTypeFormSections: View {
    @Binding var draft: SimpleDayTypeDraft

    var body: some View {
        Section("Day Type") {
            TextField("Name", text: $draft.title)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("day-type-name")
        }

        Section("Usual Week") {
            WeekdayPicker(selectedDays: $draft.assignedWeekdays, occupiedDays: [])
            if draft.assignedWeekdays.isEmpty {
                Text("Choose at least one day.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }

        ForEach($draft.blocks) { $block in
            Section {
                TextField("Block name", text: $block.title)
                    .textInputAutocapitalization(.words)

                LabeledContent("Starts") {
                    MinuteTimePicker(minuteOfDay: $block.startMinuteOfDay)
                }
                LabeledContent("Ends") {
                    MinuteTimePicker(minuteOfDay: $block.endMinuteOfDay)
                }

                ForEach($block.taskBlueprints) { $task in
                    TextField("Checklist item", text: $task.title)
                }
                .onDelete { offsets in
                    block.taskBlueprints.remove(atOffsets: offsets)
                }

                Button {
                    block.taskBlueprints.append(TaskBlueprint(title: ""))
                } label: {
                    Label("Add Checklist Item", systemImage: "plus")
                }

                Button("Remove Block", role: .destructive) {
                    draft.blocks.removeAll { $0.id == block.id }
                }
            } header: {
                Text(block.title.isEmpty ? "Block" : block.title)
            }
        }

        Section {
            Button(action: addBlock) {
                Label("Add Block", systemImage: "plus.rectangle")
            }
        } footer: {
            Text("Blocks are sorted by start time when saved. Gaps become open time in Now.")
        }
    }

    private func addBlock() {
        let lastEnd = draft.blocks.map(\.endMinuteOfDay).max() ?? 8 * 60
        let start = min(lastEnd, 23 * 60)
        let end = min(start + 60, 24 * 60)
        draft.blocks.append(
            SimpleDayTypeBlockDraft(
                title: "New Block",
                startMinuteOfDay: start,
                endMinuteOfDay: end
            )
        )
    }
}

struct MinuteTimePicker: View {
    @Binding var minuteOfDay: Int

    var body: some View {
        DatePicker(
            "Time",
            selection: Binding(
                get: { date(for: minuteOfDay) },
                set: { minuteOfDay = snappedMinute(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .datePickerStyle(.compact)
    }

    private func date(for minute: Int) -> Date {
        let start = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .minute, value: min(max(minute, 0), 24 * 60 - 1), to: start) ?? start
    }

    private func snappedMinute(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let raw = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return min(max(Int((Double(raw) / 5).rounded()) * 5, 0), 24 * 60 - 5)
    }
}

#Preview("Activation") {
    ActivationRootView()
        .environment(PreviewSupport.store(loaded: false))
}
