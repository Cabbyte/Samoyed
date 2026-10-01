import SwiftUI

struct FeedbackSheetContext: Identifiable {
    let id = UUID()
    let target: FeedbackTarget
    let targetTitle: String
    let targetDetail: String?
    let localDay: LocalDay
    let source: FeedbackSource
}

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let context: FeedbackSheetContext
    let save: (FeedbackSentiment?, String) throws -> FeedbackEvent

    @State private var selectedSentiment: FeedbackSentiment?
    @State private var note = ""
    @State private var savedEvent: FeedbackEvent?
    @State private var validationMessage: String?
    @State private var isSaving = false
    @AccessibilityFocusState private var validationIsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let savedEvent {
                    savedSummary(savedEvent)
                } else {
                    editor
                }
            }
            .navigationTitle(savedEvent == nil ? "How did this feel?" : savedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if savedEvent != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .accessibilityIdentifier("feedback-done")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if savedEvent == nil {
                    VStack(spacing: 8) {
                        Button(action: submit) {
                            Text(isSaving ? "Saving…" : "Save Feedback")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave || isSaving)
                        .accessibilityIdentifier("feedback-save")

                        Button("Cancel") { dismiss() }
                            .frame(minHeight: 44)
                            .disabled(isSaving)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder
    private var editor: some View {
        targetSection

        Section("Quick Feedback") {
            LazyVGrid(columns: Array(
                repeating: GridItem(.flexible(), spacing: 8),
                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
            ), spacing: 8) {
                ForEach(FeedbackSentiment.allCases, id: \.self) { sentiment in
                    FeedbackSentimentRow(
                        sentiment: sentiment,
                        isSelected: selectedSentiment == sentiment
                    ) {
                        selectedSentiment = selectedSentiment == sentiment ? nil : sentiment
                        validationMessage = nil
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
        }

        Section {
            TextField("Add an optional note", text: $note, axis: .vertical)
                .lineLimit(3 ... 8)
                .accessibilityIdentifier("feedback-note")
                .onChange(of: note) { _, _ in
                    validationMessage = nil
                }
        } header: {
            Text("Note (Optional)")
        } footer: {
            Text("Feedback is saved separately. It never edits today’s plan or the source routine.")
        }

        if let validationMessage {
            Section {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.primary)
                    .accessibilityFocused($validationIsFocused)
                    .accessibilityIdentifier("feedback-validation-error")
            }
        }
    }

    private var targetSection: some View {
        Section("Target") {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.targetTitle)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                    if let targetDetail = context.targetDetail {
                        Text(targetDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } label: {
                Label("Feedback For", systemImage: "scope")
            }
        }
    }

    @ViewBuilder
    private func savedSummary(_ event: FeedbackEvent) -> some View {
        Section {
            Label(savedTitle, systemImage: savedSystemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(savedMessage(for: event))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        targetSection

        Section("Feedback") {
            LabeledContent("Sentiment", value: event.sentiment?.displayTitle ?? "Not provided")
            LabeledContent("Note") {
                Text(event.note ?? "Not provided")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(event.note == nil ? .secondary : .primary)
            }
        }
    }

    private var normalizedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        selectedSentiment != nil || !normalizedNote.isEmpty
    }

    private var savedTitle: String {
        guard let savedEvent else { return "Feedback Saved" }
        return savedEvent.syncState == .synced ? "Feedback Saved" : "Saved on this iPhone"
    }

    private var savedSystemImage: String {
        guard let savedEvent else { return "checkmark.circle.fill" }
        return savedEvent.syncState == .synced ? "checkmark.circle.fill" : "iphone"
    }

    private func savedMessage(for event: FeedbackEvent) -> String {
        switch event.syncState {
        case .synced:
            return "Your feedback was saved."
        case .pending:
            return "Your feedback is safely stored here and will sync when Samoyed is online."
        case .localOnly:
            return "Your feedback is safely stored on this iPhone. No feedback sync service is configured."
        }
    }

    private func submit() {
        guard canSave else {
            showValidation("Choose how it felt or add a note.")
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            savedEvent = try save(selectedSentiment, normalizedNote)
            validationMessage = nil
            AccessibilityNotification.Announcement(savedTitle).post()
        } catch {
            showValidation(error.localizedDescription)
        }
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        validationIsFocused = true
    }
}

private struct FeedbackSentimentRow: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let sentiment: FeedbackSentiment
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: sentiment.systemImage)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Text(sentiment.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(differentiateWithoutColor ? Color.primary : Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.accentColor : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("feedback-sentiment-\(sentiment.rawValue)")
    }
}

private extension FeedbackSentiment {
    var displayTitle: String {
        switch self {
        case .good: "Good"
        case .tooRushed: "Too Rushed"
        case .tooLoose: "Too Loose"
        case .tired: "Tired"
        case .uncomfortable: "Uncomfortable"
        }
    }

    var systemImage: String {
        switch self {
        case .good: "hand.thumbsup"
        case .tooRushed: "hare"
        case .tooLoose: "tortoise"
        case .tired: "moon.zzz"
        case .uncomfortable: "exclamationmark.circle"
        }
    }
}
