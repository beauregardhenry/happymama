import SwiftUI
import CoreData

struct ChoresView: View {
    let household: Household
    let me: Member
    @FetchRequest private var chores: FetchedResults<Chore>
    @State private var showingNew = false

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        // Kids only ever see their own chores; parents see everyone's.
        let predicate = me.isParent
            ? NSPredicate(format: "household == %@", household)
            : NSPredicate(format: "household == %@ AND assignee == %@", household, me)
        _chores = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Chore.createdAt, ascending: false)],
            predicate: predicate,
            animation: .default)
    }

    private func dueSorted(_ list: [Chore]) -> [Chore] {
        list.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
            }
        }
    }

    private var waiting: [Chore] { chores.filter { $0.status == .pendingReview } }
    private var todo: [Chore] { dueSorted(chores.filter { $0.status == .todo }) }
    private var done: [Chore] {
        Array(chores.filter { $0.status == .approved }
            .sorted { ($0.reviewedAt ?? .distantPast) > ($1.reviewedAt ?? .distantPast) }
            .prefix(30))
    }

    var body: some View {
        List {
            if !me.isParent {
                Section { BalanceCard(member: me) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if me.isParent {
                choreSection("Waiting for review", waiting)
                choreSection("To do", todo)
            } else {
                choreSection("To do", todo)
                choreSection("Waiting for approval", waiting)
            }
            choreSection("Done", done)
        }
        .overlay {
            if chores.isEmpty {
                ContentUnavailableView(
                    me.isParent ? "No chores yet" : "Nothing to do!",
                    systemImage: "checklist",
                    description: Text(me.isParent ? "Tap + to assign the first chore." : "When a parent gives you a chore, it shows up here."))
            }
        }
        .navigationTitle(me.isParent ? "Chores" : "My Chores")
        .navigationDestination(for: Chore.self) { ChoreDetailView(chore: $0, me: me) }
        .toolbar {
            if me.isParent {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Label("New Chore", systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            ChoreEditorView(household: household, me: me, chore: nil)
        }
    }

    @ViewBuilder
    private func choreSection(_ title: String, _ list: [Chore]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { chore in
                    NavigationLink(value: chore) {
                        ChoreRow(chore: chore, showAssignee: me.isParent)
                    }
                }
            }
        }
    }
}

struct BalanceCard: View {
    @ObservedObject var member: Member

    var body: some View {
        let streak = member.streak()
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Avatar(member: member, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hi, \(member.displayName)!").font(.title3.bold())
                    Text(member.reserved > 0 ? "\(member.available) points · \(member.reserved) on hold" : "\(member.available) points")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if streak > 0 {
                        Text("🔥 \(streak)-day streak").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                Spacer()
                Text("\(member.available)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
            }
            if let goal = member.goal {
                GoalProgress(member: member, goal: goal)
            }
        }
        .padding()
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct GoalProgress: View {
    @ObservedObject var member: Member
    let goal: Reward

    var body: some View {
        let reached = member.available >= Int(goal.cost)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Saving for \(goal.displayEmoji) \(goal.displayTitle)").font(.subheadline.weight(.medium))
                Spacer()
                Text(reached ? "Ready!" : "\(max(0, member.available)) / \(goal.cost)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(reached ? Color.green : Color.secondary)
            }
            ProgressView(value: member.goalProgress)
                .tint(reached ? .green : Theme.accent)
        }
    }
}

struct ChoreRow: View {
    @ObservedObject var chore: Chore
    var showAssignee: Bool

    var body: some View {
        HStack(spacing: 12) {
            if showAssignee, let assignee = chore.assignee {
                Avatar(member: assignee, size: 38)
            } else {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 38)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(chore.displayTitle).font(.headline)
                HStack(spacing: 6) {
                    if showAssignee, let assignee = chore.assignee { Text(assignee.displayName) }
                    if let due = chore.dueDate {
                        Text(dueText(due)).foregroundStyle(chore.isOverdue ? Color.red : Color.secondary)
                    }
                    if chore.takesTurns {
                        Image(systemName: "arrow.triangle.2.circlepath").accessibilityLabel("Taking turns")
                    } else if chore.recurrence.isRepeating {
                        Image(systemName: "repeat").accessibilityLabel("Repeats")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if chore.wasSentBack { StatusChip(text: "Sent back", color: .orange) }
                if chore.status == .pendingReview && showAssignee { StatusChip(text: "Needs review", color: .blue) }
            }
            Spacer()
            PointsBadge(points: Int(chore.status == .approved ? chore.awardedPoints : chore.points))
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: String {
        switch chore.status {
        case .todo: "circle"
        case .pendingReview: "hourglass"
        case .approved: "checkmark.circle.fill"
        }
    }
    private var statusColor: Color {
        switch chore.status {
        case .todo: chore.isOverdue ? .red : .secondary
        case .pendingReview: .blue
        case .approved: .green
        }
    }
}
