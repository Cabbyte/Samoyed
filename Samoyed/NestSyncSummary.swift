import SwiftUI

/// Library and account details share the same live synchronization state.
struct NestSyncSummary: View {
    let nest: NestAccountController
    var expanded = false

    private var needsAttention: Bool {
        nest.errorMessage != nil || nest.blockedOperations > 0 || nest.needsImportChoice
    }
    private var statusSymbol: String {
        if needsAttention { return "exclamationmark.circle.fill" }
        if nest.connected && nest.lastSyncedAt != nil { return "checkmark.circle.fill" }
        return "iphone"
    }
    private var statusColor: Color {
        if needsAttention { return .orange }
        return nest.connected && nest.lastSyncedAt != nil ? .green : .secondary
    }
    var body: some View {
        HStack(spacing: 14) {
            Image("NestCloudSync")
                .resizable().scaledToFit()
                .frame(width: expanded ? 44 : 34, height: expanded ? 44 : 34)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: expanded ? 4 : 2) {
                if expanded {
                    HStack(spacing: 10) {
                        Text(nest.status).font(.title2.bold())
                        statusIndicator
                    }
                    syncTime.font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Samoyed Nest").font(.body.weight(.semibold))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        statusIndicator
                        Text(nest.status)
                        if let date = nest.lastSyncedAt, !needsAttention, !nest.isSyncing {
                            Text("·")
                            Text(date, style: .relative)
                        }
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, expanded ? 10 : 2)
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var statusIndicator: some View {
        if nest.isSyncing || nest.isBusy {
            ProgressView().controlSize(.small).accessibilityLabel("正在连接或同步")
        } else {
            Image(systemName: statusSymbol).foregroundStyle(statusColor).accessibilityHidden(true)
        }
    }
    @ViewBuilder private var syncTime: some View {
        if let date = nest.lastSyncedAt {
            HStack(spacing: 4) {
                Text("上次同步 ·")
                Text(date, style: .time)
            }
        } else {
            Text(nest.user == nil ? "Routine、Checklist 与 Note 保存在本机" : "尚未完成首次同步")
        }
    }
}
