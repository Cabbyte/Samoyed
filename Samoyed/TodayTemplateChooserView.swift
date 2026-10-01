import SwiftUI

struct RoutineSelectionRequiredView: View {
    @Environment(SamoyedStore.self) private var store

    let date: LocalDay
    let title: String
    let message: String

    private var hasRoutines: Bool {
        !store.savedTemplates.isEmpty
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "square.stack.3d.up")
        } description: {
            Text("\(date.titleText). \(message)")
        } actions: {
            Button(hasRoutines ? "Choose Routine" : "Import Routine Config File") {
                store.openLibrary(destination: hasRoutines ? .routines : .routineFiles)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct TodayTemplateChooserView: View {
    @Environment(SamoyedStore.self) private var store

    let date: LocalDay
    var onApplied: (() -> Void)? = nil

    @State private var pendingChoice: PendingChoice?

    var body: some View {
        Group {
            if let chooser = try? store.todayTemplateChooserModel(for: date) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(chooser: chooser)

                        if let currentSelection = chooser.currentSelection {
                            summaryCard(
                                title: "Selected Routine",
                                template: currentSelection,
                                accentColor: Color.accentColor
                            )
                        }

                        if chooser.canChooseNoTemplate {
                            Button {
                                attemptChoice(
                                    templateID: nil,
                                    source: .noTemplate,
                                    forceReplace: false
                                )
                            } label: {
                                Label("No routine today", systemImage: "calendar.badge.minus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("today-no-routine")
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Routines")
                                .font(.title3.weight(.semibold))

                            if chooser.availableTemplates.isEmpty {
                                ContentUnavailableView(
                                    "No Routines",
                                    systemImage: "square.stack.3d.up.slash",
                                    description: Text("Import a Routine Config File from Library before choosing today’s routine.")
                                )
                            } else {
                                ForEach(chooser.availableTemplates) { template in
                                    candidateCard(template)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .confirmationDialog(
                    "Switch today’s routine?",
                    isPresented: Binding(
                        get: { pendingChoice != nil },
                        set: { if !$0 { pendingChoice = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Switch Routine", role: .destructive) {
                        guard let pendingChoice else { return }
                        attemptChoice(
                            templateID: pendingChoice.templateID,
                            source: pendingChoice.source,
                            forceReplace: true
                        )
                    }
                    Button("Keep Current Routine", role: .cancel) {
                        pendingChoice = nil
                    }
                } message: {
                    Text("Today already has execution state. Switching routines will materialize the selected routine for this date and may reset checklist completion.")
                }
            } else {
                RecoverableErrorView(
                    title: "Unable to Load Today’s Routines",
                    message: "Samoyed could not prepare today’s routine choices.",
                    retry: store.reload
                )
            }
        }
    }

    private func header(chooser: DayTemplateChooserModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chooser.requiresSelection ? "Choose Routine" : "Switch Routine")
                .font(.largeTitle.weight(.bold))

            Text(chooser.date.titleText)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Pick exactly one routine to run for this date. Samoyed will materialize it as the read-only day structure.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func candidateCard(_ template: TemplateCandidateSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.title)
                        .font(.headline)

                    if let timeRangeText = template.timeRangeText {
                        Text(timeRangeText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if template.isCurrentForToday {
                        chooserBadge(title: "Selected", tint: Color.accentColor)
                    }
                }
            }

            chooserPreview(for: template)
            chooserStats(for: template)

            Button {
                attemptChoice(
                    templateID: template.id,
                    source: .pickedTemplate,
                    forceReplace: false
                )
            } label: {
                Text(template.isCurrentForToday ? "Selected Today" : "Select for Today")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(template.isCurrentForToday)
            .accessibilityIdentifier("today-select-routine-\(template.id.uuidString)")
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func summaryCard(
        title: String,
        template: TemplateCandidateSummary,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(template.title)
                .font(.headline)

            if let timeRangeText = template.timeRangeText {
                Text(timeRangeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            chooserPreview(for: template)
        }
        .padding(18)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accentColor.opacity(0.18), lineWidth: 1.25)
        )
    }

    private func chooserPreview(for template: TemplateCandidateSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                previewChips(for: template)
            }

            VStack(alignment: .leading, spacing: 8) {
                previewChips(for: template)
            }
        }
    }

    @ViewBuilder
    private func previewChips(for template: TemplateCandidateSummary) -> some View {
        ForEach(template.previewTitles, id: \.self) { title in
            chooserBadge(title: title, tint: .primary, soft: false)
        }
    }

    private func chooserStats(for template: TemplateCandidateSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chooserBadge(title: "\(template.baseBlockCount) base", tint: .secondary)
                chooserBadge(title: "\(template.overlayCount) overlays", tint: .secondary)
                chooserBadge(title: "\(template.taskCount) tasks", tint: .secondary)
                chooserBadge(title: "\(template.reminderCount) reminders", tint: .secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                chooserBadge(title: "\(template.baseBlockCount) base", tint: .secondary)
                chooserBadge(title: "\(template.overlayCount) overlays", tint: .secondary)
                chooserBadge(title: "\(template.taskCount) tasks", tint: .secondary)
                chooserBadge(title: "\(template.reminderCount) reminders", tint: .secondary)
            }
        }
    }

    private func chooserBadge(
        title: String,
        tint: Color,
        soft: Bool = true
    ) -> some View {
        Text(title)
            .font(.footnote.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                tint.opacity(soft ? 0.12 : 0.08),
                in: Capsule()
            )
    }

    private func attemptChoice(
        templateID: UUID?,
        source: DayTemplateSelectionSource,
        forceReplace: Bool
    ) {
        do {
            let result = try store.chooseTemplate(
                for: date,
                templateID: templateID,
                source: source,
                forceReplace: forceReplace
            )

            switch result {
            case .applied:
                pendingChoice = nil
                onApplied?()

            case .requiresConfirmation:
                pendingChoice = PendingChoice(
                    templateID: templateID,
                    source: source
                )
            }
        } catch {
            store.presentError(error)
        }
    }
}

private struct PendingChoice: Equatable {
    let templateID: UUID?
    let source: DayTemplateSelectionSource
}

#Preview("Choose Today") {
    TodayTemplateChooserView(date: PreviewSupport.referenceDay)
        .environment(
            PreviewSupport.store(
                tab: .now,
                document: SamoyedDocument(
                    savedTemplates: PreviewSupport.seededDocument().savedTemplates,
                    weekdayRules: PreviewSupport.seededDocument().weekdayRules
                )
            )
        )
}
