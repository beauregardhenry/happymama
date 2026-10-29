import SwiftUI
import PhotosUI

struct ChoreDetailView: View {
    @ObservedObject var chore: Chore
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss

    @State private var showingComplete = false
    @State private var showingEdit = false
    @State private var showingSendBack = false
    @State private var confirmingDelete = false
    @State private var awardPoints = 0
    @State private var sendBackNote = ""
    @State private var error: String?

    private var isAssignee: Bool { chore.assignee?.id == me.id }

    var body: some View {
        Form {
            detailsSection

            if chore.wasSentBack {
                Section("Sent back") {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chore.reviewNote ?? "")
                            if let name = chore.reviewedByName {
                                Text("— \(name)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.orange)
                    }
                }
            }

            if chore.status == .pendingReview { turnedInSection }

            if chore.status == .approved {
                Section("Approved") {
                    Label("\(chore.awardedPoints) points awarded", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    if let date = chore.reviewedAt {
                        // No reviewer means the chore approves itself.
                        Text("\(chore.reviewedByName ?? "Automatically") · \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            actionsSection
        }
        .formStyle(.grouped)
        .navigationTitle(chore.displayTitle)
        .toolbar {
            if me.isParent && chore.status == .todo {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit", systemImage: "pencil") { showingEdit = true }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                }
            }
        }
        .onAppear { awardPoints = Int(chore.points) }
        .sheet(isPresented: $showingComplete) {
            CompleteChoreSheet(chore: chore) { note, photo in
                perform { try service.markComplete(chore, by: me, note: note, photo: photo) }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let household = chore.household {
                ChoreEditorView(household: household, me: me, chore: chore)
            }
        }
        .alert("Send back to \(chore.assignee?.displayName ?? "them")?", isPresented: $showingSendBack) {
            TextField("What needs another look?", text: $sendBackNote)
            Button("Send Back") {
                perform { try service.reject(chore, by: me, note: sendBackNote) }
                sendBackNote = ""
            }
            Button("Cancel", role: .cancel) { sendBackNote = "" }
        } message: {
            Text("No points are awarded. They'll see your note and can try again.")
        }
        .confirmationDialog("Delete this chore?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Chore", role: .destructive) {
                perform {
                    try service.deleteChore(chore, by: me)
                    dismiss()
                }
            }
        }
        .errorAlert($error)
    }

    private var detailsSection: some View {
        Section {
            if let notes = chore.notes, !notes.isEmpty {
                Text(notes)
            }
            LabeledContent("Worth") { PointsBadge(points: Int(chore.points)) }
            if let assignee = chore.assignee {
                LabeledContent("Assigned to") {
                    HStack(spacing: 6) { Text(assignee.displayEmoji); Text(assignee.displayName) }
                }
            }
            if let due = dueText(for: chore) {
                LabeledContent("Due") {
                    Text(due).foregroundStyle(chore.isOverdue ? Color.red : Color.primary)
                }
            }
            if chore.recurrence.isRepeating {
                LabeledContent("Repeats", value: chore.recurrence.summary())
            }
            if chore.autoApprove {
                LabeledContent("Approval", value: "Automatic")
            }
            if chore.takesTurns {
                LabeledContent("Taking turns", value: chore.rotation.map(\.displayName).joined(separator: " → "))
                if chore.status != .approved, let next = chore.nextAssignee {
                    LabeledContent("Next time", value: next.displayName)
                }
            }
        }
    }

    private var turnedInSection: some View {
        Section("Turned in") {
            if let date = chore.completedAt {
                Text("\(chore.assignee?.displayName ?? "They") finished this \(date.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
            if let note = chore.completionNote { Text("“\(note)”") }
            if let photo = chore.photo {
                PhotoView(data: photo)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if chore.status == .todo && isAssignee && !me.isParent {
            Section {
                Button { showingComplete = true } label: {
                    Label("I'm done!", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } footer: {
                Text(chore.autoApprove
                     ? "You'll get your points right away."
                     : "A parent will check it before you get your points.")
            }
        }

        if chore.status == .pendingReview && isAssignee {
            Section {
                Label("Waiting for a parent to approve", systemImage: "hourglass")
                Button("Take it back") { perform { try service.withdraw(chore, by: me) } }
            }
        }

        if chore.status == .pendingReview && me.isParent {
            Section("Review") {
                Stepper(value: $awardPoints, in: 0...10_000) {
                    Text("Award \(awardPoints) point\(awardPoints == 1 ? "" : "s")")
                }
                if awardPoints != Int(chore.points) {
                    Text("Usually \(chore.points). Adjust for partial or bonus credit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button { perform { try service.approve(chore, by: me, points: awardPoints) } } label: {
                    Label("Approve & Award Points", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Button(role: .destructive) { showingSendBack = true } label: {
                    Label("Send Back…", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func perform(_ work: () throws -> Void) {
        do { try work() } catch { self.error = error.localizedDescription }
    }
}

/// Asks for an optional note and photo before turning a chore in.
struct CompleteChoreSheet: View {
    let chore: Chore
    let onSubmit: (String?, Data?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var loadingPhoto = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A parent will check “\(chore.displayTitle)” before you get your points.")
                        .foregroundStyle(.secondary)
                }
                Section("Add a note (optional)") {
                    TextField("Anything they should know?", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Show your work (optional)") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photo == nil ? "Add a photo" : "Choose a different photo", systemImage: "photo")
                    }
                    if loadingPhoto { ProgressView() }
                    if let photo {
                        PhotoView(data: photo).frame(maxHeight: 220)
                        Button("Remove photo", role: .destructive) { self.photo = nil; pickerItem = nil }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Turn in chore")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Turn In") {
                        onSubmit(note, photo)
                        dismiss()
                    }
                    .disabled(loadingPhoto)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                loadingPhoto = true
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photo = ImageProcessing.jpegData(from: data)
                    }
                    loadingPhoto = false
                }
            }
        }
        .sheetFrame(height: 520)
    }
}
