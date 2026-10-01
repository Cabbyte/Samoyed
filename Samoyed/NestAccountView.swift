import SwiftUI

struct NestAccountView: View {
    @Environment(SamoyedStore.self) private var store
    @State private var address = "https://samoyed.protium.top"
    var body: some View {
        let nest = store.nest
        Form {
            Section("连接状态") {
                Text(nest.status)
                if let origin = nest.origin { Text(origin.absoluteString).font(.caption).textSelection(.enabled) }
                if let user = nest.user {
                    LabeledContent("账户", value: user.id).font(.caption)
                    LabeledContent("日程时区", value: user.timeZoneID)
                }
                if let date = nest.lastSyncedAt { LabeledContent("上次同步") { Text(date, style: .time) } }
            }
            if nest.user == nil {
                Section {
                    TextField("Nest 地址", text: $address).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("登录并连接") { Task { await nest.login(address: address, store: store) } }.disabled(nest.isBusy)
                } footer: { Text("使用系统浏览器和 Passkey 登录。未登录时仍可在本机使用 Routine、Checklist 与 Note。") }
            }
            if nest.needsImportChoice {
                Section("首次同步") {
                    Text(nest.importSummary)
                    Button("导入本机资料") { Task { await nest.bind(importLocal: true) } }.disabled(nest.isBusy)
                    Button("使用云端资料") { Task { await nest.bind(importLocal: false) } }.disabled(nest.isBusy)
                }
            }
            if let zone = nest.proposedTimeZone, !nest.needsImportChoice {
                Section("设备时区已变化") {
                    Text("将账户日程时区改为 \(zone)？历史和已执行计划保留原时区。")
                    Button("使用设备时区") { Task { await nest.confirmTimeZone() } }
                    Button("保留账户时区") { nest.retainTimeZone() }
                }
            }
            if nest.connected {
                Section {
                    Button("立即同步") { nest.scheduleSync() }
                    if nest.blockedOperations > 0 { Text("未上传的冲突修改保留在本机，请打开“同步冲突”选择要保留的版本。").foregroundStyle(.orange) }
                    NavigationLink("同步冲突") { NestNoteConflictsView() }
                    if let origin = nest.origin { Link("管理 Passkey、设备与 Agent 授权", destination: origin.appendingPathComponent("account")) }
                }
            }
            if nest.user != nil {
                Section {
                    Button("退出此账户", role: .destructive) { Task { await nest.logout() } }
                } footer: { Text("退出后显示本机模式资料。未上传的修改保留在原账户分区，重新连接该账户后继续同步。") }
            }
            if let error = nest.errorMessage { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Samoyed Nest")
        .navigationBarTitleDisplayMode(.inline)
    }
}
