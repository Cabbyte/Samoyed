import SwiftUI

struct SuggestionsInboxView: View {
    @Environment(SamoyedStore.self) private var store

    private var pending: [Suggestion] {
        store.document.suggestions
            .filter { $0.lifecycleState == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView(
                    "No Suggestions",
                    systemImage: "sparkles",
                    description: Text("Approved routines continue to run locally.")
                )
            } else {
                List {
                    suggestionSection(
                        title: "For Tomorrow",
                        suggestions: pending.filter { $0.kind == .dailyPlan }
                    )
                    suggestionSection(
                        title: "Routine Improvements",
                        suggestions: pending.filter { $0.kind == .routineImprovement }
                    )
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("suggestions-inbox")
    }

    @ViewBuilder
    private func suggestionSection(title: String, suggestions: [Suggestion]) -> some View {
        if !suggestions.isEmpty {
            Section(title) {
                ForEach(suggestions) { suggestion in
                    NavigationLink {
                        SuggestionDetailView(suggestionID: suggestion.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(suggestion.title, systemImage: suggestion.kind == .dailyPlan ? "calendar.badge.clock" : "arrow.triangle.2.circlepath")
                                .font(.body.weight(.medium))
                            if let summary = suggestion.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Text("\(suggestion.changes.count) changes · Ready to review")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .accessibilityIdentifier("suggestion-\(suggestion.id.uuidString)")
                }
            }
        }
    }
}
struct SuggestionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(SamoyedStore.self) private var store
    @State private var isConfirmingReplacement = false

    let suggestionID: UUID

    private var suggestion: Suggestion? {
        store.document.suggestions.first { $0.id == suggestionID }
    }

    var body: some View {
        Group {
            if let suggestion {
                List {
                    stateSection(suggestion)
                    if let summary = suggestion.summary, !summary.isEmpty {
                        Section("Summary") { Text(summary) }
                    }
                    if !suggestion.changes.isEmpty {
                        Section("Changes") {
                            ForEach(suggestion.changes) { change in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(change.title)
                                    if let detail = change.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    evidenceSection(suggestion)
                    actionsSection(suggestion)
                }
                .listStyle(.insetGrouped)
                .navigationTitle(suggestion.kind == .dailyPlan ? "Tomorrow’s Plan" : "Routine Improvement")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Suggestion Unavailable", systemImage: "sparkles")
            }
        }
        .confirmationDialog("Replace execution progress?", isPresented: $isConfirmingReplacement) {
            Button("Use Suggested Plan") { accept(allowReplacingExecutionState: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The target day already contains execution progress. Confirm before replacing it.")
        }
    }

    private func stateSection(_ suggestion: Suggestion) -> some View {
        Section {
            Label(stateTitle(suggestion), systemImage: stateSymbol(suggestion.lifecycleState))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if suggestion.kind == .dailyPlan, let payload = suggestion.dailyPlanPayload {
                LabeledContent("Target", value: payload.targetDate.formatted)
                if let sourceID = payload.proposedDayPlan.sourceSavedTemplateID,
                   let routine = store.savedTemplate(id: sourceID) {
                    LabeledContent("Source Routine", value: routine.title)
                }
            } else if let payload = suggestion.routineImprovementPayload,
                      let routine = store.savedTemplate(id: payload.routineID) {
                LabeledContent("Affected Routine", value: routine.title)
                LabeledContent("Current Version", value: "\(routine.revision)")
            }
        }
    }

    @ViewBuilder
    private func evidenceSection(_ suggestion: Suggestion) -> some View {
        if let evidence = suggestion.evidence {
            Section("Why This Changed") {
                if let summary = evidence.summary, !summary.isEmpty {
                    Text(summary)
                }
                if !evidence.feedbackEventIDs.isEmpty {
                    LabeledContent("Evidence", value: "\(evidence.feedbackEventIDs.count) feedback events")
                }
                Text("Assumptions are reviewed locally before any change is applied.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ suggestion: Suggestion) -> some View {
        Section {
            switch suggestion.lifecycleState {
            case .pending:
                Button {
                    accept(allowReplacingExecutionState: false)
                } label: {
                    Label(
                        suggestion.kind == .dailyPlan ? "Use Tomorrow’s Plan" : "Accept as New Routine Version",
                        systemImage: "checkmark.circle"
                    )
                }
                .accessibilityIdentifier("suggestion-accept")

                Button {
                    reject()
                } label: {
                    Label(
                        suggestion.kind == .dailyPlan ? "Keep Usual Routine" : "Reject",
                        systemImage: "xmark.circle"
                    )
                }
                .accessibilityIdentifier("suggestion-reject")

                Button {
                    if let url = URL(string: "https://chatgpt.com/?q=Review%20this%20Samoyed%20suggestion") {
                        openURL(url)
                    }
                } label: {
                    Label("Review in ChatGPT", systemImage: "arrow.up.right.square")
                }

            case .accepted:
                Label(
                    suggestion.kind == .dailyPlan ? "Accepted" : "Accepted as a New Routine Version",
                    systemImage: "checkmark.seal.fill"
                )
                Text(suggestion.kind == .routineImprovement ? "Today has not changed." : "The target date now uses the approved plan.")
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }

            case .rejected:
                Label(
                    suggestion.kind == .dailyPlan ? "Kept Usual Routine" : "Rejected",
                    systemImage: "hand.raised.fill"
                )
                Button("Done") { dismiss() }

            case .expired:
                Label("Expired", systemImage: "clock.badge.xmark")
            }
        }
    }

    private func accept(allowReplacingExecutionState: Bool) {
        do {
            try store.acceptSuggestion(
                suggestionID,
                allowReplacingExecutionState: allowReplacingExecutionState
            )
        } catch SuggestionServiceError.requiresExecutionStateConfirmation {
            isConfirmingReplacement = true
        } catch {
            store.presentError(error)
        }
    }

    private func reject() {
        do {
            try store.rejectSuggestion(suggestionID)
        } catch {
            store.presentError(error)
        }
    }

    private func stateTitle(_ suggestion: Suggestion) -> String {
        switch suggestion.lifecycleState {
        case .pending: "Ready to Review"
        case .accepted: "Accepted"
        case .rejected: suggestion.kind == .dailyPlan ? "Kept Usual Routine" : "Rejected"
        case .expired: "Expired"
        }
    }

    private func stateSymbol(_ state: SuggestionLifecycleState) -> String {
        switch state {
        case .pending: "sparkles"
        case .accepted: "checkmark.seal.fill"
        case .rejected: "hand.raised.fill"
        case .expired: "clock.badge.xmark"
        }
    }
}

private extension LocalDay {
    var formatted: String {
        DateComponents(calendar: .current, year: year, month: month, day: day)
            .date?
            .formatted(date: .abbreviated, time: .omitted) ?? "\(year)-\(month)-\(day)"
    }
}
