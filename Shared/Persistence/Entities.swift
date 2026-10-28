import CoreData

enum Role: String, CaseIterable, Identifiable {
    case parent, kid
    var id: String { rawValue }
    var title: String { self == .parent ? "Parent" : "Kid" }
}

enum ChoreStatus: String {
    case todo, pendingReview, approved

    /// How far along the chore is, for picking between duplicates.
    var progress: Int {
        switch self {
        case .todo: 0
        case .pendingReview: 1
        case .approved: 2
        }
    }
}

enum RedemptionStatus: String {
    case requested, approved, denied
}

enum EntryKind: String {
    case chore, redemption
}

@objc(Household)
final class Household: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var parentCode: String?
    @NSManaged var createdAt: Date?
    @NSManaged var members: NSSet?
    @NSManaged var chores: NSSet?
    @NSManaged var rewards: NSSet?
    @NSManaged var redemptions: NSSet?
    @NSManaged var entries: NSSet?

    var displayName: String { name ?? "Our Household" }
    var memberList: [Member] {
        ((members as? Set<Member>) ?? []).sorted {
            if $0.isParent != $1.isParent { return $0.isParent }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
    var kids: [Member] { memberList.filter { !$0.isParent } }
    var parents: [Member] { memberList.filter { $0.isParent } }
}

@objc(Member)
final class Member: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var roleRaw: String?
    @NSManaged var emoji: String?
    @NSManaged var colorIndex: Int16
    @NSManaged var appleUserID: String?
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?
    @NSManaged var assignedChores: NSSet?
    @NSManaged var redemptions: NSSet?
    @NSManaged var entries: NSSet?

    var role: Role {
        get { Role(rawValue: roleRaw ?? "") ?? .kid }
        set { roleRaw = newValue.rawValue }
    }
    var isParent: Bool { role == .parent }
    var displayName: String { name ?? "Someone" }
    var displayEmoji: String { emoji ?? (isParent ? "🌻" : "🦊") }
    var isClaimed: Bool { appleUserID != nil }

    /// Newest first. Two parents acting on the same chore or request from different
    /// devices can each record an entry before they sync, so only one per source counts.
    var entryList: [PointEntry] {
        PointEntry.unique((entries as? Set<PointEntry>) ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    /// Points earned minus points spent.
    var balance: Int { entryList.reduce(0) { $0 + Int($1.amount) } }
    /// Points tied up in redemption requests a parent hasn't decided yet.
    var reserved: Int {
        ((redemptions as? Set<Redemption>) ?? [])
            .filter { $0.status == .requested }
            .reduce(0) { $0 + Int($1.cost) }
    }
    var available: Int { balance - reserved }
}

@objc(Chore)
final class Chore: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var notes: String?
    @NSManaged var points: Int32
    @NSManaged var statusRaw: String?
    @NSManaged var dueDate: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var recurrenceRaw: String?
    @NSManaged var weekdayMask: Int16
    @NSManaged var completedAt: Date?
    @NSManaged var completionNote: String?
    @NSManaged var photo: Data?
    @NSManaged var reviewedAt: Date?
    @NSManaged var reviewedByName: String?
    @NSManaged var reviewNote: String?
    @NSManaged var awardedPoints: Int32
    /// For a repeating chore's next copy: the chore whose approval created it.
    @NSManaged var sourceChoreID: UUID?
    @NSManaged var household: Household?
    @NSManaged var assignee: Member?

    var displayTitle: String { title ?? "Chore" }
    var status: ChoreStatus {
        get { ChoreStatus(rawValue: statusRaw ?? "") ?? .todo }
        set { statusRaw = newValue.rawValue }
    }
    var recurrence: RecurrenceRule {
        get { RecurrenceRule(kind: Recurrence(rawValue: recurrenceRaw ?? "") ?? .none, weekdayMask: Int(weekdayMask)) }
        set { recurrenceRaw = newValue.kind.rawValue; weekdayMask = Int16(newValue.weekdayMask) }
    }
    var isOverdue: Bool { isOverdue() }
    func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard status == .todo, let dueDate else { return false }
        return dueDate < calendar.startOfDay(for: now)
    }
    var wasSentBack: Bool { status == .todo && !(reviewNote ?? "").isEmpty }
}

@objc(Reward)
final class Reward: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var emoji: String?
    @NSManaged var cost: Int32
    @NSManaged var isActive: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?

    var displayTitle: String { title ?? "Reward" }
    var displayEmoji: String { emoji ?? "🎁" }
}

@objc(Redemption)
final class Redemption: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var rewardTitle: String?
    @NSManaged var rewardEmoji: String?
    @NSManaged var cost: Int32
    @NSManaged var statusRaw: String?
    @NSManaged var requestedAt: Date?
    @NSManaged var decidedAt: Date?
    @NSManaged var decidedByName: String?
    @NSManaged var household: Household?
    @NSManaged var member: Member?

    var status: RedemptionStatus {
        get { RedemptionStatus(rawValue: statusRaw ?? "") ?? .requested }
        set { statusRaw = newValue.rawValue }
    }
    var displayTitle: String { rewardTitle ?? "Reward" }
    var displayEmoji: String { rewardEmoji ?? "🎁" }
}

@objc(PointEntry)
final class PointEntry: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var amount: Int32
    @NSManaged var reason: String?
    @NSManaged var kindRaw: String?
    @NSManaged var date: Date?
    @NSManaged var choreID: UUID?
    @NSManaged var redemptionID: UUID?
    @NSManaged var household: Household?
    @NSManaged var member: Member?

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw ?? "") ?? .chore }
        set { kindRaw = newValue.rawValue }
    }

    /// What this entry pays out for. Entries with the same source are duplicates.
    var sourceKey: String {
        switch kind {
        case .chore: choreID.map { "chore-\($0.uuidString)" } ?? "entry-\(id?.uuidString ?? "")"
        case .redemption: redemptionID.map { "redemption-\($0.uuidString)" } ?? "entry-\(id?.uuidString ?? "")"
        }
    }

    /// One entry per source, keeping the one every device would pick (lowest id).
    static func unique(_ entries: some Sequence<PointEntry>) -> [PointEntry] {
        Dictionary(grouping: entries, by: \.sourceKey).values.compactMap { $0.min(by: syncOrder) }
    }
}

/// A tie-break that every device computes the same way, so duplicate cleanup converges.
func syncOrder<T: NSManagedObject>(_ a: T, _ b: T) -> Bool {
    let ida = (a.value(forKey: "id") as? UUID)?.uuidString ?? ""
    let idb = (b.value(forKey: "id") as? UUID)?.uuidString ?? ""
    return ida < idb
}
