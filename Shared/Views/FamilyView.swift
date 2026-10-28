import SwiftUI
import CoreData
import UserNotifications

struct FamilyView: View {
    let household: Household
    @ObservedObject var me: Member
    @EnvironmentObject private var identity: Identity
    @EnvironmentObject private var box: PersistenceBox
    @EnvironmentObject private var service: HouseholdService
    @EnvironmentObject private var sharedDevice: SharedDevice
    @FetchRequest private var members: FetchedResults<Member>
    @State private var showingAdd = false
    @State private var notificationsEnabled = false
    @State private var editingCode = false
    @State private var newCode = ""
    @State private var error: String?

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        _members = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Member.name, ascending: true)],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default)
    }

    private var sortedMembers: [Member] {
        members.sorted {
            if $0.isParent != $1.isParent { return $0.isParent }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section("People") {
                ForEach(sortedMembers) { member in
                    NavigationLink(value: member) { MemberRow(member: member, isMe: member == me) }
                }
            }

            if me.isParent {
                Section {
                    LabeledContent("Household", value: household.displayName)
                    if let code = household.parentCode {
                        LabeledContent("Parent code") {
                            HStack {
                                Text(code).font(.body.monospacedDigit()).textSelection(.enabled)
                                Button("Change") { newCode = ""; editingCode = true }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    #if !LOCAL_ONLY
                    if box.persistence.isOwner(of: household) {
                        InviteButton(household: household)
                    } else {
                        Text("Only the person who created the household can send invitations.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    #endif
                } header: {
                    Text("Household")
                } footer: {
                    Text("To bring someone in: add them with the + button, then send an invitation. They pick their profile when they join. Share the parent code only with other parents.")
                }
            }

            if me.isParent {
                Section {
                    Toggle("Shared family device", isOn: Binding(
                        get: { sharedDevice.isEnabled },
                        set: { $0 ? sharedDevice.enable(as: me) : (sharedDevice.isEnabled = false) }))
                } footer: {
                    Text("For a device the whole family uses, like a kitchen iPad. Everyone taps their own profile to start, parents enter the parent code, and it goes back to the profile list whenever the app is closed.")
                }
            }

            Section("This device") {
                #if LOCAL_ONLY
                Label("Local test build: data stays on this device.", systemImage: "internaldrive")
                Menu("Switch user") {
                    ForEach(sortedMembers.filter(\.isClaimed)) { member in
                        Button("\(member.displayEmoji) \(member.displayName)") { identity.actAs(member) }
                    }
                }
                #else
                Label("Synced with iCloud", systemImage: "icloud")
                #endif
                if notificationsEnabled {
                    Label("Notifications on", systemImage: "bell.fill")
                } else {
                    Button("Turn on notifications", systemImage: "bell") {
                        Task {
                            notificationsEnabled = await AppEnvironment.shared.notifier.requestAuthorization()
                            AppEnvironment.shared.syncNotifications()
                        }
                    }
                }
            }
        }
        .navigationTitle("Family")
        .navigationDestination(for: Member.self) { MemberDetailView(member: $0, me: me) }
        .toolbar {
            if me.isParent {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Label("Add Person", systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $showingAdd) { MemberEditorView(household: household, me: me, member: nil) }
        .alert("New parent code", isPresented: $editingCode) {
            SecureField("4 to 8 digits", text: $newCode)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
            Button("Save") { saveCode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Parents use this code to join the household and to open their profile on a shared device.")
        }
        .errorAlert($error)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsEnabled = settings.authorizationStatus == .authorized
        }
    }
}

extension FamilyView {
    private func saveCode() {
        do { try service.setParentCode(newCode, for: household, by: me) } catch { self.error = error.localizedDescription }
        newCode = ""
    }
}

struct MemberRow: View {
    @ObservedObject var member: Member
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            Avatar(member: member)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName + (isMe ? " (you)" : "")).font(.headline)
                HStack(spacing: 6) {
                    Text(member.role.title)
                    if !member.isClaimed { StatusChip(text: "Not joined yet", color: .orange) }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !member.isParent { PointsBadge(points: member.balance) }
        }
    }
}

struct MemberDetailView: View {
    @ObservedObject var member: Member
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingRemove = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Avatar(member: member, size: 56)
                    VStack(alignment: .leading) {
                        Text(member.displayName).font(.title2.bold())
                        Text(member.role.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !member.isParent {
                        VStack(alignment: .trailing) {
                            Text("\(member.balance)")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.accent)
                            Text("points").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !member.isParent {
                Section("Points history") {
                    if member.entryList.isEmpty {
                        Text("No points yet.").foregroundStyle(.secondary)
                    }
                    ForEach(member.entryList) { entry in
                        HStack {
                            Image(systemName: entry.kind == .chore ? "checkmark.circle.fill" : "gift.fill")
                                .foregroundStyle(entry.kind == .chore ? Color.green : Theme.accent)
                            VStack(alignment: .leading) {
                                Text(entry.reason ?? "")
                                if let date = entry.date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(entry.amount > 0 ? "+\(entry.amount)" : "\(entry.amount)")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(entry.amount >= 0 ? Color.green : Color.secondary)
                        }
                    }
                }
            }

            if me.isParent {
                Section {
                    Button("Edit", systemImage: "pencil") { showingEdit = true }
                    if member != me {
                        if member.isClaimed {
                            Button("Reset sign-in", systemImage: "person.crop.circle.badge.xmark") {
                                do { try service.resetSignIn(of: member, by: me) } catch { self.error = error.localizedDescription }
                            }
                        }
                        Button("Remove from household", systemImage: "trash", role: .destructive) { confirmingRemove = true }
                    }
                } footer: {
                    if member != me { Text("Reset sign-in lets someone else pick this profile, for example after changing Apple ID.") }
                }
            }
        }
        .navigationTitle(member.displayName)
        .sheet(isPresented: $showingEdit) {
            if let household = member.household { MemberEditorView(household: household, me: me, member: member) }
        }
        .confirmationDialog("Remove \(member.displayName)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove and delete their chores and points", role: .destructive) {
                do {
                    try service.removeMember(member, by: me)
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
        }
        .errorAlert($error)
    }
}

struct MemberEditorView: View {
    let household: Household
    let me: Member
    let member: Member?
    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var role: Role
    @State private var emoji: String
    @State private var error: String?

    init(household: Household, me: Member, member: Member?) {
        self.household = household
        self.me = me
        self.member = member
        _name = State(initialValue: member?.name ?? "")
        _role = State(initialValue: member?.role ?? .kid)
        _emoji = State(initialValue: member?.displayEmoji ?? Theme.kidEmojis[household.memberList.count % Theme.kidEmojis.count])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Role", selection: $role) {
                        ForEach(Role.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Avatar") {
                    EmojiPicker(selection: $emoji, options: role == .parent ? Theme.parentEmojis : Theme.kidEmojis)
                }
                Section {
                    Text(role == .parent
                         ? "Parents assign chores, approve completed work and manage rewards."
                         : "Kids get chores, mark them done, and earn points once a parent approves.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(member == nil ? "Add Person" : "Edit Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            if let member {
                                try service.updateMember(member, name: name, role: role, emoji: emoji, by: me)
                            } else {
                                try service.addMember(name: name, role: role, emoji: emoji, to: household, by: me)
                            }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
            .errorAlert($error)
        }
        .sheetFrame(height: 460)
    }
}
