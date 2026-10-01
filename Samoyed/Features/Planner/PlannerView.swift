import SwiftUI

struct PlannerView: View {
    @Environment(\.openURL) private var openURL
    @Environment(SamoyedStore.self) private var store

    private var settings: PlannerSettings { store.document.plannerSettings }

    var body: some View {
        List {
            statusSection
            capabilitySection
            actionSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Planner")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("planner-screen")
    }

    private var statusSection: some View {
        Section {
            Label(statusTitle, systemImage: statusSymbol)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(statusMessage)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var capabilitySection: some View {
        Section("How Planner Works") {
            Label("Reads approved routines", systemImage: "book.closed")
            Label("Reads feedback you saved", systemImage: "bubble.left")
            Label("Creates suggestions for your review", systemImage: "sparkles")
            Label("Cannot silently change your running plan", systemImage: "hand.raised")
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            switch settings.connectionState {
            case .disconnected:
                Button("Open ChatGPT to Connect") { openPlannerURL() }
                    .accessibilityIdentifier("planner-connect")
                Button("Learn How It Works") { openPlannerURL() }

            case .connected:
                LabeledContent("Provider", value: "ChatGPT")
                LabeledContent("Status", value: "Connected")
                if let planningTime = settings.planningTime,
                   let hour = planningTime.hour,
                   let minute = planningTime.minute {
                    LabeledContent("Tomorrow Planning", value: String(format: "%02d:%02d", hour, minute))
                }
                Button("Open in ChatGPT") { openPlannerURL() }
                Button("Change Planning Time") { store.presentErrorMessage("Planning-time updates require a configured Planner service.") }
                Button("Disconnect", role: .destructive) { store.disconnectPlanner() }

            case .unavailable, .needsAttention:
                Button("Open ChatGPT") { openPlannerURL() }
                Button("Try Again") { store.presentErrorMessage("Planner is unavailable. Your usual routine continues locally.") }
            }
        }
    }

    private var statusTitle: String {
        switch settings.connectionState {
        case .disconnected: "Planner Not Connected"
        case .connected: "Planner Connected"
        case .unavailable: "Planner Unavailable"
        case .needsAttention: "Planner Needs Attention"
        }
    }

    private var statusSymbol: String {
        switch settings.connectionState {
        case .disconnected: "link.badge.plus"
        case .connected: "checkmark.circle.fill"
        case .unavailable: "wifi.slash"
        case .needsAttention: "exclamationmark.triangle.fill"
        }
    }

    private var statusMessage: String {
        switch settings.connectionState {
        case .disconnected:
            "Samoyed runs locally without Planner. Connect only when a real external service is available."
        case .connected:
            "Planner can propose changes. Every suggestion still requires your approval."
        case .unavailable:
            "Planner is unavailable. Your usual routine continues locally."
        case .needsAttention:
            "Planner needs attention, but it does not block local routines."
        }
    }

    private func openPlannerURL() {
        if let url = settings.externalURL
            ?? URL(string: "https://chatgpt.com/?q=Connect%20Samoyed%20Planner") {
            openURL(url)
        }
    }
}
