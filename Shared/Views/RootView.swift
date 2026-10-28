import SwiftUI
import CoreData

struct RootView: View {
    @EnvironmentObject private var identity: Identity
    @EnvironmentObject private var box: PersistenceBox
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Household.createdAt, ascending: true)])
    private var households: FetchedResults<Household>
    // Observed so the view refreshes when someone claims a profile.
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Member.createdAt, ascending: true)])
    private var members: FetchedResults<Member>

    var body: some View {
        if let error = box.persistence.loadError {
            ContentUnavailableView(
                "Couldn't open your data",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription))
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch identity.status {
        case .checking:
            ProgressView("Checking iCloud…")
        case .unavailable(let message):
            ICloudRequiredView(message: message)
        case .available:
            if let userID = identity.userID {
                if let household = households.first {
                    if let me = members.first(where: { $0.household == household && $0.appleUserID == userID }) {
                        MainView(household: household, me: me)
                    } else {
                        ClaimProfileView(household: household, userID: userID)
                    }
                } else {
                    WelcomeView(userID: userID)
                }
            } else {
                ProgressView()
            }
        }
    }
}

struct ICloudRequiredView: View {
    let message: String
    @EnvironmentObject private var identity: Identity

    var body: some View {
        ContentUnavailableView {
            Label("iCloud needed", systemImage: "icloud.slash")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await identity.refresh() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

struct EmojiPicker: View {
    @Binding var selection: String
    let options: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { emoji in
                    Button { selection = emoji } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(selection == emoji ? Theme.accent.opacity(0.25) : Color.secondary.opacity(0.12), in: Circle())
                            .overlay(Circle().stroke(selection == emoji ? Theme.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(emoji)
                    .accessibilityAddTraits(selection == emoji ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// First launch: create a household.
struct WelcomeView: View {
    let userID: String
    @EnvironmentObject private var service: HouseholdService
    @State private var householdName = ""
    @State private var yourName = ""
    @State private var emoji = Theme.parentEmojis[0]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Text("🏡").font(.system(size: 56))
                        Text("Welcome to Happy Mama").font(.title2.bold())
                        Text("Assign chores, check them off, and cheer everyone on with points.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section("Start a household") {
                    TextField("Household name", text: $householdName)
                    TextField("Your name", text: $yourName)
                    EmojiPicker(selection: $emoji, options: Theme.parentEmojis)
                    Button("Create Household") { create() }
                        .buttonStyle(.borderedProminent)
                        .disabled(householdName.trimmed.isEmpty || yourName.trimmed.isEmpty)
                }
                Section("Joining a household?") {
                    Text("Open the invitation you were sent on this device. Your household appears here once it syncs.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Happy Mama")
        }
        .errorAlert($error)
    }

    private func create() {
        do {
            try service.createHousehold(name: householdName, yourName: yourName, emoji: emoji, userID: userID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Shown after joining a shared household: pick which profile is you.
struct ClaimProfileView: View {
    let household: Household
    let userID: String
    @EnvironmentObject private var service: HouseholdService
    @FetchRequest private var members: FetchedResults<Member>
    @State private var pendingParent: Member?
    @State private var code = ""
    @State private var newName = ""
    @State private var newEmoji = Theme.kidEmojis[0]
    @State private var error: String?

    init(household: Household, userID: String) {
        self.household = household
        self.userID = userID
        _members = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Member.name, ascending: true)],
            predicate: NSPredicate(format: "household == %@ AND appleUserID == nil", household))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Welcome to \(household.displayName)! Which one is you?")
                        .font(.headline)
                }
                if !members.isEmpty {
                    Section("Pick your profile") {
                        ForEach(members) { member in
                            Button { choose(member) } label: {
                                HStack {
                                    Avatar(member: member)
                                    VStack(alignment: .leading) {
                                        Text(member.displayName).font(.headline)
                                        Text(member.role.title).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Not on the list?") {
                    TextField("Your name", text: $newName)
                    EmojiPicker(selection: $newEmoji, options: Theme.kidEmojis)
                    Button("Join as a Kid") { joinAsKid() }
                        .disabled(newName.trimmed.isEmpty)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Who are you?")
        }
        .alert("Parent code", isPresented: Binding(get: { pendingParent != nil }, set: { if !$0 { pendingParent = nil } })) {
            TextField("6-digit code", text: $code)
            Button("Continue") {
                if let member = pendingParent { claim(member, code: code) }
                code = ""
            }
            Button("Cancel", role: .cancel) { code = "" }
        } message: {
            Text("Parent profiles are protected. Ask a parent for the code under Family.")
        }
        .errorAlert($error)
    }

    private func choose(_ member: Member) {
        if member.isParent { pendingParent = member } else { claim(member, code: nil) }
    }

    private func claim(_ member: Member, code: String?) {
        do { try service.claim(member, userID: userID, parentCode: code) } catch { self.error = error.localizedDescription }
    }

    private func joinAsKid() {
        do { try service.joinAsKid(name: newName, emoji: newEmoji, userID: userID, household: household) } catch { self.error = error.localizedDescription }
    }
}
