import SwiftUI

/// Pick several ready-made chores and who should do them, and add them in one go.
struct ChoreLibraryView: View {
    let household: Household
    let me: Member

    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var kids: Set<Member>
    @State private var takeTurns = false
    @State private var error: String?

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        _kids = State(initialValue: Set(household.kids))
    }

    private var pickedTemplates: [ChoreLibrary.Template] {
        ChoreLibrary.templates.filter { picked.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if household.kids.isEmpty {
                        Text("Add a kid in the Family tab first.").foregroundStyle(.secondary)
                    }
                    ForEach(household.kids) { kid in
                        Button { toggle(kid) } label: {
                            HStack {
                                Avatar(member: kid, size: 32)
                                Text(kid.displayName)
                                Spacer()
                                Image(systemName: kids.contains(kid) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(kids.contains(kid) ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(kids.contains(kid) ? .isSelected : [])
                    }
                    if kids.count > 1 {
                        Toggle("Take turns on repeating chores", isOn: $takeTurns)
                    }
                } header: {
                    Text("For")
                } footer: {
                    if kids.count > 1 && !takeTurns { Text("Each kid gets their own copy.") }
                }

                ForEach(ChoreLibrary.Age.allCases) { age in
                    Section(age.title) {
                        ForEach(ChoreLibrary.templates(for: age)) { template in
                            row(template)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Chore Ideas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? "Add" : "Add \(picked.count)") { add() }
                        .disabled(picked.isEmpty || kids.isEmpty)
                }
            }
            .errorAlert($error)
        }
        .sheetFrame(height: 680)
    }

    private func row(_ template: ChoreLibrary.Template) -> some View {
        let on = picked.contains(template.id)
        return Button {
            if on { picked.remove(template.id) } else { picked.insert(template.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(on ? Theme.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                    Text(template.repeats == .none ? "One-off" : template.repeats.title)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                PointsBadge(points: template.points)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ kid: Member) {
        if kids.contains(kid) { kids.remove(kid) } else { kids.insert(kid) }
    }

    private func add() {
        let ordered = household.kids.filter { kids.contains($0) }
        do {
            try service.addFromLibrary(pickedTemplates, assignees: ordered, takeTurns: takeTurns, in: household, by: me)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
