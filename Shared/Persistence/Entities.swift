import CoreData

enum Role: String, CaseIterable, Identifiable {
    case parent, kid
    var id: String { rawValue }
    var title: String { self == .parent ? "Parent" : "Kid" }
}

enum ChoreStatus: String {
    case todo, pendingReview, approved
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

    var entryList: [PointEntry] {
        ((entries as? Set<PointEntry>) ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
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
    var isOverdue: Bool {
        guard status == .todo, let dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
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
    @NSManaged var household: Household?
    @NSManaged var member: Member?

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw ?? "") ?? .chore }
        set { kindRaw = newValue.rawValue }
    }
}
