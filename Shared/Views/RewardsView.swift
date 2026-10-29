import SwiftUI
import CoreData

struct RewardsView: View {
    let household: Household
    @ObservedObject var me: Member
    @EnvironmentObject private var service: HouseholdService
    @FetchRequest private var rewards: FetchedResults<Reward>
    @FetchRequest private var myRequests: FetchedResults<Redemption>
    @State private var editing: Reward?
    @State private var showingNew = false
    @State private var confirming: Reward?
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        _rewards = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Reward.cost, ascending: true)],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default)
        _myRequests = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Redemption.requestedAt, ascending: false)],
            predicate: NSPredicate(format: "member == %@", me),
            animation: .default)
    }

    private var visibleRewards: [Reward] {
        me.isParent ? Array(rewards) : rewards.filter(\.isActive)
    }

    var body: some View {
        List {
            if !me.isParent {
                Section { BalanceCard(member: me) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(visibleRewards) { reward in
                    if me.isParent {
                        Button { editing = reward } label: { rewardLabel(reward) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", role: .destructive) { delete(reward) }
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = reward }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(reward) }
                            }
                    } else {
                        // At the largest text sizes the buttons go under the name.
                        let layout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                            : AnyLayout(HStackLayout())
                        layout {
                            rewardLabel(reward)
                            HStack(spacing: 16) {
                                let isGoal = me.goal?.id == reward.id
                                Button { setGoal(isGoal ? nil : reward) } label: {
                                    Image(systemName: isGoal ? "star.fill" : "star")
                                        .foregroundStyle(isGoal ? Color.orange : Color.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(isGoal ? "Stop saving for this" : "Save for this")
                                Button("Redeem") { confirming = reward }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(me.available < Int(reward.cost))
                            }
                        }
                    }
                }
            } header: {
                Text(me.isParent ? "Reward store" : "Spend your points")
            } footer: {
                if !me.isParent && !visibleRewards.isEmpty {
                    Text("Tap the star on a reward to save for it.")
                }
            }

            if !me.isParent && !myRequests.isEmpty {
                Section("My requests") {
                    ForEach(myRequests.prefix(20)) { request in
                        HStack {
                            Text("\(request.displayEmoji) \(request.displayTitle)")
                            Spacer()
                            switch request.status {
                            case .requested: StatusChip(text: "Waiting", color: .blue)
                            case .approved: StatusChip(text: "Approved", color: .green)
                            case .denied: StatusChip(text: "Not approved", color: .secondary)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if visibleRewards.isEmpty {
                ContentUnavailableView(
                    me.isParent ? "No rewards yet" : "No rewards yet",
                    systemImage: "gift",
                    description: Text(me.isParent
                        ? "Add things kids can spend points on, like movie night or extra screen time."
                        : "Ask a parent to add some rewards."))
            }
        }
        .navigationTitle("Rewards")
        .toolbar {
            if me.isParent {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Label("New Reward", systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $showingNew) { RewardEditorView(household: household, me: me, reward: nil) }
        .sheet(item: $editing) { RewardEditorView(household: household, me: me, reward: $0) }
        .confirmationDialog(
            confirming.map { "Ask for \($0.displayTitle)?" } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let reward = confirming {
                Button("Ask for it (\(reward.cost) pts)") {
                    do { try service.requestRedemption(of: reward, by: me) } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("Your points are only spent if a parent says yes.")
        }
        .errorAlert($error)
    }

    private func rewardLabel(_ reward: Reward) -> some View {
        HStack(spacing: 12) {
            Text(reward.displayEmoji).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(reward.displayTitle).font(.headline)
                if !reward.isActive { Text("Hidden from kids").font(.caption).foregroundStyle(.secondary) }
                // Kids' rows also hold the star and Redeem, so the cost moves under the name.
                if !me.isParent { PointsBadge(points: Int(reward.cost)) }
            }
            Spacer()
            if me.isParent { PointsBadge(points: Int(reward.cost)) }
        }
        .contentShape(Rectangle())
    }

    private func delete(_ reward: Reward) {
        do { try service.deleteReward(reward, by: me) } catch { self.error = error.localizedDescription }
    }

    private func setGoal(_ reward: Reward?) {
        do { try service.setGoal(reward, for: me, by: me) } catch { self.error = error.localizedDescription }
    }
}

struct RewardEditorView: View {
    let household: Household
    let me: Member
    let reward: Reward?
    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var emoji: String
    @State private var cost: Int
    @State private var isActive: Bool
    @State private var error: String?

    init(household: Household, me: Member, reward: Reward?) {
        self.household = household
        self.me = me
        self.reward = reward
        _title = State(initialValue: reward?.title ?? "")
        _emoji = State(initialValue: reward?.displayEmoji ?? Theme.rewardEmojis[0])
        _cost = State(initialValue: Int(reward?.cost ?? 50))
        _isActive = State(initialValue: reward?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reward") {
                    TextField("Name (e.g. Movie night)", text: $title)
                    EmojiPicker(selection: $emoji, options: Theme.rewardEmojis)
                }
                Section("Cost") {
                    HStack {
                        Text("Points")
                        Spacer()
                        TextField("Points", value: $cost, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Stepper("Points", value: $cost, in: 1...100_000, step: 5).labelsHidden()
                    }
                }
                Section {
                    Toggle("Available to kids", isOn: $isActive)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(reward == nil ? "New Reward" : "Edit Reward")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try service.saveReward(reward, title: title, emoji: emoji, cost: cost, isActive: isActive, in: household, by: me)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(title.trimmed.isEmpty)
                }
            }
            .errorAlert($error)
        }
        .sheetFrame(height: 460)
    }
}
