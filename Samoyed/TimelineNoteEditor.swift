import SwiftUI

struct TimelineNoteEditor: View {
    @Environment(SamoyedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var note: TimelineNote
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextEditor(text: $note.text).frame(minHeight: 160).accessibilityLabel("Note text")
                }
                Section("When it happened") {
                    DatePicker("Time", selection: $note.occurredAt)
                        .environment(\.timeZone, TimeZone(identifier: note.timeZoneID) ?? .current)
                    Text(note.timeZoneID).font(.caption).foregroundStyle(.secondary)
                }
                if note.blockInstanceID != nil {
                    Section { Label("Linked to this day's block", systemImage: "link") }
                }
                if store.document.timelineNotes.contains(where: { $0.id == note.id }) {
                    Section {
                        Button("Delete Note", role: .destructive) { confirmDelete = true }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Timeline Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        note.updatedAt = .now
                        do { try store.saveTimelineNote(note); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }.disabled(note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $confirmDelete) {
                Button("Delete Note", role: .destructive) {
                    do { try store.deleteTimelineNote(note); dismiss() }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        }
    }
}
