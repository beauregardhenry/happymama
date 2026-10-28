import SwiftUI
import CoreData

/// The home screen of a shared family device: everyone taps their own face.
struct ProfilePickerView: View {
    let household: Household
    @EnvironmentObject private var sharedDevice: SharedDevice
    @FetchRequest private var members: FetchedResults<Member>
    @State private var pendingParent: Member?
    @State private var code = ""
    @State private var error: String?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(household: Household) {
        self.household = household
        _members = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Member.name, ascending: true)],
            predicate: NSPredicate(format: "household == %@", household))
    }

    private var kids: [Member] { members.filter { !$0.isParent } }
    private var parents: [Member] { members.filter(\.isParent) }
    /// A centered row of tiles: up to four across on a big screen, two on a phone.
    private func columns(for count: Int) -> [GridItem] {
        #if os(iOS)
        let perRow = sizeClass == .compact ? 2 : 4
        #else
        let perRow = 4
        #endif
        return Array(repeating: GridItem(.flexible(maximum: 180), spacing: 20), count: max(1, min(count, perRow)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 6) {
                        Text("Who's using Happy Mama?").font(.largeTitle.bold())
                        Text(household.displayName).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                    if !kids.isEmpty {
                        LazyVGrid(columns: columns(for: kids.count), spacing: 20) {
                            ForEach(kids) { tile($0) }
                        }
                    }
                    if !parents.isEmpty {
                        VStack(spacing: 12) {
                            Text("Parents").font(.headline).foregroundStyle(.secondary)
                            LazyVGrid(columns: columns(for: parents.count), spacing: 20) {
                                ForEach(parents) { tile($0) }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(item: $pendingParent) { parent in
            ParentCodeSheet(parent: parent, code: $code) { submit(parent) }
        }
        .errorAlert($error)
    }

    private func tile(_ member: Member) -> some View {
        Button { choose(member) } label: {
            VStack(spacing: 10) {
                Avatar(member: member, size: 96)
                Text(member.displayName).font(.title3.weight(.semibold)).lineLimit(1)
                if member.isParent {
                    Label("Code", systemImage: "lock.fill").labelStyle(.iconOnly).foregroundStyle(.secondary)
                } else {
                    PointsBadge(points: member.available)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.color(Int(member.colorIndex)).opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(member.isParent ? "\(member.displayName), parent, needs code" : member.displayName)
    }

    private func choose(_ member: Member) {
        if member.isParent {
            code = ""
            pendingParent = member
        } else {
            signIn(member, code: nil)
        }
    }

    private func submit(_ parent: Member) {
        pendingParent = nil
        signIn(parent, code: code)
        code = ""
    }

    private func signIn(_ member: Member, code: String?) {
        do { try sharedDevice.signIn(member, code: code) } catch { self.error = error.localizedDescription }
    }
}

private struct ParentCodeSheet: View {
    let parent: Member
    @Binding var code: String
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Avatar(member: parent, size: 48)
                        Text(parent.displayName).font(.title3.bold())
                    }
                }
                Section {
                    SecureField("Parent code", text: $code)
                        .focused($focused)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        #endif
                        .onSubmit(onSubmit)
                } footer: {
                    Text("Any parent can find or change the code under Family.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Enter code")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: onSubmit).disabled(code.trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .sheetFrame(width: 380, height: 360)
        .presentationDetents([.medium])
    }
}
