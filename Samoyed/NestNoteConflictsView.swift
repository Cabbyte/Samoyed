import SwiftUI

struct NestNoteConflictsView: View {
    @Environment(SamoyedStore.self) private var store
    @State private var domainConflicts: [NestDomainConflict] = []
    @State private var conflicts: [NestNoteConflict] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if conflicts.isEmpty && domainConflicts.isEmpty && errorMessage == nil {
                ContentUnavailableView("没有同步冲突", systemImage: "checkmark.circle", description: Text("所有修改都已完成同步。"))
            }
            ForEach(conflicts) { conflict in
                Section {
                    Text("On this device").font(.subheadline.bold())
                    Text(conflict.local.text).textSelection(.enabled)
                    Text(conflict.local.occurredAt.formatted()).font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("In Nest").font(.subheadline.bold())
                    if conflict.remoteDeleted {
                        Label("Deleted on another device", systemImage: "trash")
                    } else if let remote = conflict.remote {
                        Text(remote.text).textSelection(.enabled)
                        Text(remote.occurredAt.formatted()).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("This note could not be saved to Nest.")
                    }
                    Button(conflict.remoteDeleted ? "Keep Mine as a New Note" : "Keep My Edit") {
                        resolve(conflict, choice: .keepLocal)
                    }
                    Button(conflict.remoteDeleted ? "Keep the Deletion" : "Use Nest Version") {
                        resolve(conflict, choice: .keepRemote)
                    }
                } footer: {
                    Text("Both versions remain in the local recovery archive after you choose.")
                }
            }
            ForEach(domainConflicts) { conflict in
                Section {
                    Text("本机修改").font(.subheadline.bold())
                    Text(conflict.localSummary).textSelection(.enabled)
                    Divider()
                    Text("Nest 中的版本").font(.subheadline.bold())
                    Text(conflict.remoteSummary).textSelection(.enabled)
                    if conflict.canKeepLocal { Button("保留本机修改") { resolveDomain(conflict, keepLocal: true) } }
                    Button("使用 Nest 版本") { resolveDomain(conflict, keepLocal: false) }
                } header: { Text("日程修改冲突") }
                footer: { Text("两侧资料会先保留在本机恢复档案中。保留本机修改后会重新校验时间范围与修订。") }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("同步冲突")
        .task { reload() }
    }

    private func resolve(_ conflict: NestNoteConflict, choice: NestNoteConflictChoice) {
        do { try store.resolveNoteConflict(conflict, choice: choice); reload() }
        catch { errorMessage = error.localizedDescription }
    }
    private func resolveDomain(_ conflict: NestDomainConflict, keepLocal: Bool) {
        do { try store.resolveDomainConflict(conflict, keepLocal: keepLocal); reload() }
        catch { errorMessage = error.localizedDescription }
    }
    private func reload() {
        do { conflicts = try store.noteConflicts(); domainConflicts = try store.domainConflicts(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
