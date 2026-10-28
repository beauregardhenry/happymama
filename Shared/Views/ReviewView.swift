import SwiftUI
import CoreData

/// Parents' inbox: chores to confirm and rewards to approve.
struct ReviewView: View {
    let household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @FetchRequest private var chores: FetchedResults<Chore>
    @FetchRequest private var requests: FetchedResults<Redemption>
    @State private var error: String?

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        _chores = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Chore.completedAt, ascending: true)],
            predicate: NSPredicate(format: "household == %@ AND statusRaw == %@", household, ChoreStatus.pendingReview.rawValue),
            animation: .default)
        _requests = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Redemption.requestedAt, ascending: true)],
            predicate: NSPredicate(format: "household == %@ AND statusRaw == %@", household, RedemptionStatus.requested.rawValue),
            animation: .default)
    }

    var body: some View {
        List {
            if !chores.isEmpty {
                Section("Chores to confirm") {
                    ForEach(chores) { chore in
                        NavigationLink(value: chore) {
                            ChoreRow(chore: chore, showAssignee: true)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Approve") { approve(chore) }.tint(.green)
                        }
                        .contextMenu {
                            Button("Approve (\(chore.points) pts)", systemImage: "checkmark.seal") { approve(chore) }
                        }
                    }
                }
            }
            if !requests.isEmpty {
                Section("Reward requests") {
                    ForEach(requests) { request in
                        RedemptionRow(request: request, me: me, onError: { error = $0 })
                    }
                }
            }
        }
        .overlay {
            if chores.isEmpty && requests.isEmpty {
                ContentUnavailableView(
                    "All caught up",
                    systemImage: "checkmark.seal",
                    description: Text("Finished chores and reward requests show up here for you to confirm."))
            }
        }
        .navigationTitle("Review")
        .navigationDestination(for: Chore.self) { ChoreDetailView(chore: $0, me: me) }
        .errorAlert($error)
    }

    private func approve(_ chore: Chore) {
        do { try service.approve(chore, by: me) } catch { self.error = error.localizedDescription }
    }
}

struct RedemptionRow: View {
    @ObservedObject var request: Redemption
    let me: Member
    let onError: (String) -> Void
    @EnvironmentObject private var service: HouseholdService

    var body: some View {
        HStack(spacing: 12) {
            if let kid = request.member { Avatar(member: kid, size: 38) }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(request.displayEmoji) \(request.displayTitle)").font(.headline)
                Text("\(request.member?.displayName ?? "Someone") · \(request.cost) pts")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Deny") { decide(false) }.buttonStyle(.bordered).tint(.red)
            Button("Approve") { decide(true) }.buttonStyle(.borderedProminent).tint(.green)
        }
        .buttonStyle(.borderless)
    }

    private func decide(_ approve: Bool) {
        do { try service.decide(request, approve: approve, by: me) } catch { onError(error.localizedDescription) }
    }
}
