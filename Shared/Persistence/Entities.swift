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
    /// The reward a kid is saving toward.
    @NSManaged var goalRewardID: UUID?
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

    /// The reward this kid is saving for, while it's still offered.
    var goal: Reward? {
        guard let goalRewardID else { return nil }
        return ((household?.rewards as? Set<Reward>) ?? []).first { $0.id == goalRewardID && $0.isActive }
    }
    /// How close `available` is to the goal, from 0 to 1.
    var goalProgress: Double {
        guard let cost = goal?.cost, cost > 0 else { return 0 }
        return min(1, Double(max(0, available)) / Double(cost))
    }

    /// Days in a row on which this kid turned in a chore that wasn't sent back, ending
    /// today or yesterday. Yesterday still counts so the streak doesn't read 0 every morning.
    func streak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(((assignedChores as? Set<Chore>) ?? []).compactMap { chore -> Date? in
            guard chore.status != .todo, let done = chore.completedAt else { return nil }
            return calendar.startOfDay(for: done)
        })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        var count = 0
        while days.contains(day), let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            count += 1
            day = previous
        }
        return count
    }
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
    /// For a chore kids take turns on: the member ids in turn order, comma-separated.
    @NSManaged var rotationRaw: String?
    /// Minutes after midnight the chore is due by, or -1 for any time that day.
    @NSManaged var dueMinute: Int16
    @NSManaged var household: Household?
    @NSManaged var assignee: Member?

    var rotationIDs: [UUID] {
        get { (rotationRaw ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { rotationRaw = newValue.isEmpty ? nil : newValue.map(\.uuidString).joined(separator: ",") }
    }
    /// The kids taking turns who are still in the household, in turn order.
    var rotation: [Member] {
        let kids = household?.kids ?? []
        return rotationIDs.compactMap { id in kids.first { $0.id == id } }
    }
    var takesTurns: Bool { rotationIDs.count > 1 }
    /// Who the next copy goes to: the next kid in the rotation, or the same kid if there's no one else.
    var nextAssignee: Member? {
        let kids = rotation
        guard kids.count > 1 else { return kids.first ?? assignee }
        guard let assignee, let index = kids.firstIndex(of: assignee) else { return kids.first }
        return kids[(index + 1) % kids.count]
    }

    var displayTitle: String { title ?? "Chore" }
    var status: ChoreStatus {
        get { ChoreStatus(rawValue: statusRaw ?? "") ?? .todo }
        set { statusRaw = newValue.rawValue }
    }
    var recurrence: RecurrenceRule {
        get { RecurrenceRule(kind: Recurrence(rawValue: recurrenceRaw ?? "") ?? .none, weekdayMask: Int(weekdayMask)) }
        set { recurrenceRaw = newValue.kind.rawValue; weekdayMask = Int16(newValue.weekdayMask) }
    }
    /// The time of day it's due by, in minutes after midnight, if a parent set one.
    var dueTime: Int? {
        get { dueMinute >= 0 ? Int(dueMinute) : nil }
        set { dueMinute = Int16(newValue.map { min(max($0, 0), 24 * 60 - 1) } ?? -1) }
    }
    /// The moment it's due: the due time on the due date, or the end of that day.
    func dueAt(calendar: Calendar = .current) -> Date? {
        guard let dueDate else { return nil }
        let day = calendar.startOfDay(for: dueDate)
        if let dueTime { return calendar.date(byAdding: .minute, value: dueTime, to: day) }
        return calendar.date(byAdding: .day, value: 1, to: day)
    }
    var isOverdue: Bool { isOverdue() }
    func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard status == .todo, let due = dueAt(calendar: calendar) else { return false }
        return due <= now
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
