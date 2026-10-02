import SwiftUI

struct NestAccountView: View {
    @Environment(SamoyedStore.self) private var store
    @State private var address = "https://samoyed.protium.top"

    var body: some View {
        let nest = store.nest
        List {
            Section {
                NestSyncSummary(nest: nest, expanded: true)
                    .accessibilityIdentifier("nest-sync-summary")
                if nest.connected {
                    Button { nest.scheduleSync() } label: {
                        HStack(spacing: 16) {
                            Image("NestRefresh").accessibilityHidden(true)
                            Text("立即同步").fontWeight(.semibold)
                        }
                        .foregroundStyle(.tint)
                        .padding(.vertical, 4)
                    }
                    .disabled(nest.isBusy || nest.isSyncing)
                    .accessibilityIdentifier("nest-sync-now")
                }
            }
            if let error = nest.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if nest.user == nil {
                Section {
                    TextField("Nest 地址", text: $address)
                        .textContentType(.URL).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("nest-server-address")
                    Button("登录并连接") {
                        Task { await nest.login(address: address, store: store) }
                    }
                    .disabled(nest.isBusy)
                    .accessibilityIdentifier("nest-login")
                } header: { sectionTitle("连接账户") }
                footer: {
                    Text("使用系统浏览器和 Passkey 登录。未登录时仍可在本机使用 Routine、Checklist 与 Note。")
                }
            }
            if nest.needsImportChoice {
                Section {
                    Text(nest.importSummary)
                    Button("导入本机资料") { Task { await nest.bind(importLocal: true) } }
                        .disabled(nest.isBusy)
                    Button("使用云端资料") { Task { await nest.bind(importLocal: false) } }
                        .disabled(nest.isBusy)
                } header: { sectionTitle("首次同步") }
            }
            if nest.connected {
                Section {
                    NavigationLink { NestNoteConflictsView() } label: {
                        LabeledContent("同步冲突") {
                            Text(conflictCount == 0 ? "无冲突" : "\(conflictCount) 项待处理")
                                .foregroundStyle(conflictCount == 0 ? Color.secondary : Color.orange)
                        }
                    }
                    .accessibilityIdentifier("nest-conflicts")
                    if let user = nest.user {
                        LabeledContent("日程时区") {
                            Text(timeZoneDescription(user.timeZoneID))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                } header: { sectionTitle("同步与日程") }
                footer: {
                    if conflictCount > 0 {
                        Text("未上传的冲突修改保留在本机，请打开“同步冲突”选择要保留的版本。")
                    }
                }
            }
            if let zone = nest.proposedTimeZone, !nest.needsImportChoice {
                Section {
                    Text("将账户日程时区改为 \(zone)？历史和已执行计划保留原时区。")
                    Button("使用设备时区") { Task { await nest.confirmTimeZone() } }
                    Button("保留账户时区") { nest.retainTimeZone() }
                } header: { sectionTitle("设备时区已变化") }
            }
            if let user = nest.user {
                Section {
                    if let origin = nest.origin {
                        LabeledContent("Nest 服务") {
                            Text(origin.host() ?? origin.absoluteString)
                                .font(.footnote).textSelection(.enabled)
                        }
                    }
                    LabeledContent("账户 ID") {
                        Text(user.id).font(.footnote)
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled).accessibilityLabel(user.id)
                    }
                    if let origin = nest.origin {
                        Link(destination: origin.appendingPathComponent("account")) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("账户与安全").foregroundStyle(.tint)
                                    Text("Passkey、设备与 Agent 授权")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 12)
                                Image("NestExternalLink").foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 3)
                        }
                        .accessibilityIdentifier("nest-account-security")
                    }
                } header: { sectionTitle("账户") }
                Section {
                    Button("退出此账户", role: .destructive) { Task { await nest.logout() } }
                        .disabled(nest.isBusy).accessibilityIdentifier("nest-logout")
                } footer: {
                    Text("退出后切换为本机资料。未上传的修改会保留，重新登录此账户后继续同步。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(24)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .environment(\.defaultMinListRowHeight, 50)
        .navigationTitle("Samoyed Nest")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var conflictCount: Int {
        let archived = ((try? store.noteConflicts().count) ?? 0)
            + ((try? store.domainConflicts().count) ?? 0)
        return max(store.nest.blockedOperations, archived)
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline).foregroundStyle(Color(uiColor: .secondaryLabel)).textCase(nil)
    }
    private func timeZoneDescription(_ identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        let minutes = zone.secondsFromGMT() / 60
        let offset = "UTC\(minutes >= 0 ? "+" : "−")\(abs(minutes) / 60)"
            + (minutes % 60 == 0 ? "" : String(format: ":%02d", abs(minutes) % 60))
        let city = identifier == "Asia/Shanghai" ? "上海"
            : (identifier.split(separator: "/").last.map(String.init) ?? identifier)
                .replacingOccurrences(of: "_", with: " ")
        return "\(city) · \(offset)"
    }
}
