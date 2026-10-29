import SwiftUI

/// Creates a chore (for one or more kids) or edits one that hasn't been turned in.
struct ChoreEditorView: View {
    let household: Household
    let me: Member
    let chore: Chore?

    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HouseholdService.ChoreDraft
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var selected: Set<Member>
    @State private var error: String?

    init(household: Household, me: Member, chore: Chore?) {
        self.household = household
        self.me = me
        self.chore = chore
        var draft = HouseholdService.ChoreDraft()
        if let chore {
            draft.title = chore.title ?? ""
            draft.notes = chore.notes ?? ""
            draft.points = Int(chore.points)
            draft.recurrence = chore.recurrence
            draft.dueDate = chore.dueDate
            draft.takeTurns = chore.takesTurns
            draft.autoApprove = chore.autoApprove
        }
        _draft = State(initialValue: draft)
        _hasDue = State(initialValue: chore?.dueDate != nil)
        _due = State(initialValue: chore?.dueDate ?? Date())
        _hasTime = State(initialValue: chore?.dueTime != nil)
        // The picker needs a date; only its hour and minute are used. New times start at 5pm.
        let minutes = chore?.dueTime ?? 17 * 60
        _time = State(initialValue: Calendar.current.date(byAdding: .minute, value: minutes,
                                                          to: Calendar.current.startOfDay(for: Date())) ?? Date())
        if let chore, chore.takesTurns {
            _selected = State(initialValue: Set(chore.rotation))
        } else {
            _selected = State(initialValue: chore?.assignee.map { [$0] } ?? [])
        }
    }

    private var isEditing: Bool { chore != nil }

    private var turnsHint: String {
        guard draft.takeTurns else { return "Each person gets their own copy to complete." }
        guard draft.recurrence.isRepeating else { return "Choose how often it repeats below; it moves to the next person each time." }
        let names = household.kids.filter { selected.contains($0) }.map(\.displayName)
        return "One chore that moves to the next person each time it repeats: " + names.joined(separator: " → ") + "."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chore") {
                    TextField("What needs doing?", text: $draft.title)
                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    HStack {
                        Text("Points")
                        Spacer()
                        TextField("Points", value: $draft.points, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Stepper("Points", value: $draft.points, in: 0...10_000, step: 5)
                            .labelsHidden()
                    }
                    Toggle("Approve automatically", isOn: $draft.autoApprove)
                } footer: {
                    Text(draft.autoApprove
                         ? "Points are awarded as soon as it's marked done. Good for small daily habits."
                         : "Awarded only after a parent confirms the chore is done.")
                }

                Section(isEditing ? "Assigned to" : "Assign to") {
                    if household.kids.isEmpty {
                        Text("Add a kid in the Family tab first.").foregroundStyle(.secondary)
                    }
                    ForEach(household.kids) { kid in
                        Button { toggle(kid) } label: {
                            HStack {
                                Avatar(member: kid, size: 32)
                                Text(kid.displayName)
                                Spacer()
                                if selected.contains(kid) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                } else {
                                    Image(systemName: "circle").foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(kid) ? .isSelected : [])
                    }
                    if selected.count > 1 || draft.takeTurns {
                        Toggle("Take turns", isOn: $draft.takeTurns)
                            .onChange(of: draft.takeTurns) { _, on in
                                // An edited chore without turns belongs to one kid again: whoever has it now.
                                if !on, isEditing, let current = chore?.assignee { selected = [current] }
                            }
                        Text(turnsHint).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Schedule") {
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Due", selection: $due, displayedComponents: .date)
                        Toggle("By a certain time", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        }
                    }
                    Picker("Repeat", selection: $draft.recurrence.kind) {
                        ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
                    }
                    if draft.recurrence.kind == .weekly {
                        WeekdayPicker(weekdays: Binding(
                            get: { draft.recurrence.weekdays },
                            set: { draft.recurrence.weekdays = $0 }))
                    }
                }
                .onChange(of: draft.recurrence.kind) { _, kind in
                    if kind != .none { hasDue = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Chore" : "New Chore")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Assign") { save() }
                        .disabled(draft.title.trimmed.isEmpty)
                }
            }
            .errorAlert($error)
        }
        .sheetFrame(height: 640)
    }

    private func toggle(_ kid: Member) {
        if isEditing && !draft.takeTurns {
            selected = [kid]
        } else if selected.contains(kid) {
            selected.remove(kid)
        } else {
            selected.insert(kid)
        }
    }

    private func save() {
        draft.dueDate = hasDue ? due : nil
        let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
        draft.dueTime = hasDue && hasTime ? (clock.hour ?? 0) * 60 + (clock.minute ?? 0) : nil
        if selected.count < 2 { draft.takeTurns = false }
        let ordered = household.kids.filter { selected.contains($0) }
        do {
            if let chore {
                try service.updateChore(chore, with: draft, assignees: ordered, by: me)
            } else {
                try service.createChores(draft, assignees: ordered, in: household, by: me)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct WeekdayPicker: View {
    @Binding var weekdays: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let names = Calendar.current.weekdaySymbols
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = weekdays.contains(day)
                Button {
                    if on { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(on ? Theme.accent : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
