import SwiftUI
import CoreData

enum AppSection: String, Identifiable, Hashable {
    case chores, review, rewards, family
    var id: String { rawValue }

    func title(isParent: Bool) -> String {
        switch self {
        case .chores: isParent ? "Chores" : "My Chores"
        case .review: "Review"
        case .rewards: "Rewards"
        case .family: "Family"
        }
    }

    var icon: String {
        switch self {
        case .chores: "checklist"
        case .review: "checkmark.seal"
        case .rewards: "gift"
        case .family: "person.2"
        }
    }
}

struct MainView: View {
    let household: Household
    @ObservedObject var me: Member
    /// Set on a shared family device: hands the device to someone else.
    var onSwitchUser: (() -> Void)?
    @State private var selection: AppSection? = .chores
    /// Keep the sidebar showing (even on a portrait iPad) so kids can always see the sections.
    @State private var columns = NavigationSplitViewVisibility.all
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @FetchRequest private var pendingChores: FetchedResults<Chore>
    @FetchRequest private var pendingRedemptions: FetchedResults<Redemption>

    init(household: Household, me: Member, onSwitchUser: (() -> Void)? = nil) {
        self.household = household
        self.me = me
        self.onSwitchUser = onSwitchUser
        _pendingChores = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "household == %@ AND statusRaw == %@", household, ChoreStatus.pendingReview.rawValue))
        _pendingRedemptions = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "household == %@ AND statusRaw == %@", household, RedemptionStatus.requested.rawValue))
    }

    private var sections: [AppSection] {
        me.isParent ? [.chores, .review, .rewards, .family] : [.chores, .rewards, .family]
    }
    private var reviewCount: Int { pendingChores.count + pendingRedemptions.count }

    var body: some View {
        layout
            .task { AppEnvironment.shared.syncNotifications() }
            .onChange(of: me.role) { _, _ in
                if !sections.contains(selection ?? .chores) { selection = .chores }
            }
    }

    @ViewBuilder
    private func content(_ section: AppSection) -> some View {
        switch section {
        case .chores: ChoresView(household: household, me: me)
        case .review: ReviewView(household: household, me: me)
        case .rewards: RewardsView(household: household, me: me)
        case .family: FamilyView(household: household, me: me)
        }
    }

    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if sizeClass == .regular { sidebarLayout } else { tabLayout }
        #else
        sidebarLayout
        #endif
    }

    @ViewBuilder
    private var switchUserButton: some View {
        if let onSwitchUser {
            Button(action: onSwitchUser) {
                Label("Switch", systemImage: "person.2.circle")
            }
            .accessibilityLabel("Switch person")
        }
    }

    #if os(iOS)
    private var tabLayout: some View {
        TabView(selection: Binding(get: { selection ?? .chores }, set: { selection = $0 })) {
            ForEach(sections) { section in
                NavigationStack {
                    content(section)
                        .toolbar {
                            if onSwitchUser != nil {
                                ToolbarItem(placement: .topBarLeading) { switchUserButton }
                            }
                        }
                }
                .tabItem { Label(section.title(isParent: me.isParent), systemImage: section.icon) }
                .badge(section == .review ? reviewCount : 0)
                .tag(section)
            }
        }
    }
    #endif

    private var sidebarLayout: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(sections, selection: $selection) { section in
                Label(section.title(isParent: me.isParent), systemImage: section.icon)
                    .badge(section == .review ? reviewCount : 0)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    Avatar(member: me, size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(me.displayName).font(.headline)
                        Text(household.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    switchUserButton
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        } detail: {
            NavigationStack { content(selection ?? .chores) }
                .id(selection)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
