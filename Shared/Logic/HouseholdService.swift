import CoreData

enum ServiceError: LocalizedError {
    case notAllowed(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .notAllowed(let message), .invalid(let message): message
        }
    }
}

/// All the rules of the app live here: who may do what, and what each action changes.
/// Views call these methods and never mutate chores or points directly.
@MainActor
final class HouseholdService: ObservableObject {
    let persistence: PersistenceController
    var calendar = Calendar.current
    /// Local-only builds give every added member a stand-in sign-in so they can be tested on one device.
    var autoClaimNewMembers: Bool

    var context: NSManagedObjectContext { persistence.viewContext }

    init(persistence: PersistenceController, autoClaimNewMembers: Bool = false) {
        self.persistence = persistence
        self.autoClaimNewMembers = autoClaimNewMembers
    }

    // MARK: Household and members

    @discardableResult
    func createHousehold(name: String, yourName: String, emoji: String, userID: String) throws -> Household {
        let name = name.trimmed, yourName = yourName.trimmed
        guard !name.isEmpty else { throw ServiceError.invalid("Give your household a name.") }
        guard !yourName.isEmpty else { throw ServiceError.invalid("Enter your name.") }

        let household = try make(Household.self)
        household.id = UUID()
        household.name = name
        household.createdAt = Date()
        household.parentCode = String(format: "%06d", Int.random(in: 0...999_999))

        let me = try insert(Member.self, into: household)
        me.id = UUID()
        me.name = yourName
        me.role = .parent
        me.emoji = emoji
        me.colorIndex = 0
        me.appleUserID = userID
        me.createdAt = Date()
        me.household = household
        try save()
        return household
    }

    @discardableResult
    func addMember(name: String, role: Role, emoji: String, to household: Household, by me: Member) throws -> Member {
        try requireParent(me)
        let name = name.trimmed
        guard !name.isEmpty else { throw ServiceError.invalid("Enter a name.") }
        let userID = autoClaimNewMembers ? "local-" + UUID().uuidString : nil
        let member = try newMember(name: name, role: role, emoji: emoji, userID: userID, household: household)
        try save()
        return member
    }

    func updateMember(_ member: Member, name: String, role: Role, emoji: String, by me: Member) throws {
        try requireParent(me)
        let name = name.trimmed
        guard !name.isEmpty else { throw ServiceError.invalid("Enter a name.") }
        if member.role == .parent, role == .kid, (member.household?.parents.count ?? 0) <= 1 {
            throw ServiceError.invalid("A household needs at least one parent.")
        }
        if member.id == me.id, role == .kid {
            throw ServiceError.invalid("You can't make yourself a kid.")
        }
        member.name = name
        member.role = role
        member.emoji = emoji
        try save()
    }

    func removeMember(_ member: Member, by me: Member) throws {
        try requireParent(me)
        guard member.id != me.id else { throw ServiceError.invalid("You can't remove yourself.") }
        if member.isParent, (member.household?.parents.count ?? 0) <= 1 {
            throw ServiceError.invalid("A household needs at least one parent.")
        }
        context.delete(member)
        try save()
    }

    /// Lets someone else pick this profile again (e.g. after a new Apple ID).
    func resetSignIn(of member: Member, by me: Member) throws {
        try requireParent(me)
        guard member.id != me.id else { throw ServiceError.invalid("You can't reset your own sign-in.") }
        member.appleUserID = nil
        try save()
    }

    /// Lets parents pick a code they'll remember; it unlocks parent profiles
    /// when joining and on a shared family device.
    func setParentCode(_ code: String, for household: Household, by me: Member) throws {
        try requireParent(me)
        let code = code.trimmed
        guard (4...8).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw ServiceError.invalid("Use 4 to 8 digits.")
        }
        household.parentCode = code
        try save()
    }

    /// Links the signed-in iCloud user to an existing profile. Parent profiles
    /// need the household's parent code so a kid can't pick one.
    func claim(_ member: Member, userID: String, parentCode: String?) throws {
        guard member.appleUserID == nil else { throw ServiceError.invalid("Someone has already signed in as \(member.displayName).") }
        if member.isParent {
            guard let expected = member.household?.parentCode, parentCode?.trimmed == expected else {
                throw ServiceError.notAllowed("That parent code isn't right. A parent can find it under Family.")
            }
        }
        member.appleUserID = userID
        try save()
    }

    @discardableResult
    func joinAsKid(name: String, emoji: String, userID: String, household: Household) throws -> Member {
        let name = name.trimmed
        guard !name.isEmpty else { throw ServiceError.invalid("Enter your name.") }
        let member = try newMember(name: name, role: .kid, emoji: emoji, userID: userID, household: household)
        try save()
        return member
    }

    private func newMember(name: String, role: Role, emoji: String, userID: String?, household: Household) throws -> Member {
        let member = try insert(Member.self, into: household)
        member.id = UUID()
        member.name = name
        member.role = role
        member.emoji = emoji
        member.colorIndex = Int16(household.memberList.count % Theme.palette.count)
        member.appleUserID = userID
        member.createdAt = Date()
        member.household = household
        return member
    }

    // MARK: Chores

    struct ChoreDraft {
        var title = ""
        var notes = ""
        var points = 10
        var dueDate: Date?
        var recurrence = RecurrenceRule()
    }

    @discardableResult
    func createChores(_ draft: ChoreDraft, assignees: [Member], in household: Household, by me: Member) throws -> [Chore] {
        try requireParent(me)
        guard !assignees.isEmpty else { throw ServiceError.invalid("Choose who should do it.") }
        let title = try validated(draft, assignees: assignees)
        let created = try assignees.map { kid in
            try newChore(from: draft, title: title, assignee: kid, household: household)
        }
        try save()
        return created
    }

    func updateChore(_ chore: Chore, with draft: ChoreDraft, assignee: Member, by me: Member) throws {
        try requireParent(me)
        guard chore.status == .todo else { throw ServiceError.invalid("Only chores that haven't been turned in can be edited.") }
        let title = try validated(draft, assignees: [assignee])
        chore.title = title
        chore.notes = draft.notes.trimmed
        chore.points = Int32(max(0, draft.points))
        chore.dueDate = draft.dueDate.map { calendar.startOfDay(for: $0) }
        chore.recurrence = draft.recurrence
        if chore.assignee?.id != assignee.id {
            chore.assignee = assignee
            chore.reviewNote = nil
        }
        try save()
    }

    func deleteChore(_ chore: Chore, by me: Member) throws {
        try requireParent(me)
        context.delete(chore)
        try save()
    }

    /// A kid says they're done. Nothing is awarded until a parent confirms.
    func markComplete(_ chore: Chore, by me: Member, note: String?, photo: Data?) throws {
        guard chore.assignee?.id == me.id, !me.isParent else {
            throw ServiceError.notAllowed("Only the person a chore is assigned to can mark it done.")
        }
        guard chore.status == .todo else { throw ServiceError.invalid("This chore was already turned in.") }
        chore.status = .pendingReview
        chore.completedAt = Date()
        chore.completionNote = note?.trimmed.nilIfEmpty
        chore.photo = photo
        chore.reviewNote = nil
        try save()
    }

    /// Takes a turned-in chore back before a parent has looked at it.
    func withdraw(_ chore: Chore, by me: Member) throws {
        guard chore.assignee?.id == me.id else { throw ServiceError.notAllowed("This isn't your chore.") }
        guard chore.status == .pendingReview else { throw ServiceError.invalid("This chore isn't waiting for approval.") }
        chore.status = .todo
        chore.completedAt = nil
        chore.completionNote = nil
        chore.photo = nil
        try save()
    }

    /// A parent confirms the chore. This is the only place chore points are awarded.
    /// `points` overrides the chore's value (partial or bonus credit).
    func approve(_ chore: Chore, by me: Member, points: Int? = nil) throws {
        try requireParent(me)
        guard chore.status == .pendingReview else { throw ServiceError.invalid("This chore isn't waiting for approval.") }
        guard let kid = chore.assignee, let household = chore.household else { throw ServiceError.invalid("This chore has no owner.") }

        let awarded = max(0, points ?? Int(chore.points))
        chore.status = .approved
        chore.awardedPoints = Int32(awarded)
        chore.reviewedAt = Date()
        chore.reviewedByName = me.name
        chore.reviewNote = nil

        let entry = try addEntry(Int32(awarded), kind: .chore, reason: chore.displayTitle, to: kid, in: household)
        entry.choreID = chore.id

        try scheduleNextOccurrence(after: chore)
        try save()
    }

    /// A parent sends the chore back to the kid with a note. No points are awarded.
    func reject(_ chore: Chore, by me: Member, note: String) throws {
        try requireParent(me)
        guard chore.status == .pendingReview else { throw ServiceError.invalid("This chore isn't waiting for approval.") }
        chore.status = .todo
        chore.reviewNote = note.trimmed.nilIfEmpty ?? "Please take another look."
        chore.reviewedAt = Date()
        chore.reviewedByName = me.name
        chore.completedAt = nil
        chore.completionNote = nil
        chore.photo = nil
        try save()
    }

    /// Returns the trimmed title once the draft passes the rules shared by creating and editing.
    private func validated(_ draft: ChoreDraft, assignees: [Member]) throws -> String {
        let title = draft.title.trimmed
        guard !title.isEmpty else { throw ServiceError.invalid("Give the chore a title.") }
        guard assignees.allSatisfy({ !$0.isParent }) else { throw ServiceError.invalid("Chores can only be assigned to kids.") }
        if draft.recurrence.isRepeating, draft.dueDate == nil {
            throw ServiceError.invalid("Repeating chores need a due date to start from.")
        }
        return title
    }

    private func newChore(from draft: ChoreDraft, title: String, assignee: Member, household: Household) throws -> Chore {
        let chore = try insert(Chore.self, into: household)
        chore.id = UUID()
        chore.title = title
        chore.notes = draft.notes.trimmed
        chore.points = Int32(max(0, draft.points))
        chore.status = .todo
        chore.dueDate = draft.dueDate.map { calendar.startOfDay(for: $0) }
        chore.createdAt = Date()
        chore.recurrence = draft.recurrence
        chore.household = household
        chore.assignee = assignee
        return chore
    }

    /// Repeating chores get their next copy once the current one is approved.
    private func scheduleNextOccurrence(after chore: Chore) throws {
        let rule = chore.recurrence
        guard rule.isRepeating, let household = chore.household, let kid = chore.assignee else { return }
        // Late chores repeat from today, not from the missed date.
        let base = max(chore.dueDate ?? Date(), calendar.startOfDay(for: Date()))
        guard let next = rule.nextDate(after: base, calendar: calendar) else { return }
        var draft = ChoreDraft()
        draft.notes = chore.notes ?? ""
        draft.points = Int(chore.points)
        draft.dueDate = next
        draft.recurrence = rule
        let copy = try newChore(from: draft, title: chore.displayTitle, assignee: kid, household: household)
        copy.sourceChoreID = chore.id
    }

    // MARK: Sync duplicates

    /// Two parents can approve the same chore or reward request on different devices
    /// before either syncs. Each device then records its own point entry and, for a
    /// repeating chore, its own next copy. Balances already count one entry per source;
    /// this deletes the extras so every device ends up with the same records.
    /// The keeper is chosen the same way on every device, so the deletions never collide.
    func resolveSyncDuplicates(in household: Household) throws {
        let entries = (household.entries as? Set<PointEntry>) ?? []
        let keptEntries = Set(PointEntry.unique(entries).map(\.objectID))
        for entry in entries where !keptEntries.contains(entry.objectID) {
            context.delete(entry)
        }

        let copies = ((household.chores as? Set<Chore>) ?? []).filter { $0.sourceChoreID != nil }
        for group in Dictionary(grouping: copies, by: \.sourceChoreID).values where group.count > 1 {
            // Keep the copy the kid has made the most progress on.
            let keeper = group.max { a, b in
                a.status.progress != b.status.progress ? a.status.progress < b.status.progress : syncOrder(b, a)
            }
            for chore in group where chore !== keeper {
                context.delete(chore)
            }
        }
        try save()
    }

    // MARK: Rewards

    @discardableResult
    func saveReward(_ reward: Reward?, title: String, emoji: String, cost: Int, isActive: Bool,
                    in household: Household, by me: Member) throws -> Reward {
        try requireParent(me)
        let title = title.trimmed
        guard !title.isEmpty else { throw ServiceError.invalid("Give the reward a name.") }
        guard cost > 0 else { throw ServiceError.invalid("A reward needs to cost at least 1 point.") }
        let target = try reward ?? insert(Reward.self, into: household)
        if reward == nil {
            target.id = UUID()
            target.createdAt = Date()
            target.household = household
        }
        target.title = title
        target.emoji = emoji.trimmed.nilIfEmpty ?? "🎁"
        target.cost = Int32(cost)
        target.isActive = isActive
        try save()
        return target
    }

    /// A kid picks a reward to save toward, or a parent picks it for them. nil clears it.
    func setGoal(_ reward: Reward?, for kid: Member, by me: Member) throws {
        guard !kid.isParent else { throw ServiceError.invalid("Only kids save toward rewards.") }
        guard me.isParent || me.id == kid.id else { throw ServiceError.notAllowed("You can only pick your own goal.") }
        if let reward, !reward.isActive || reward.household != kid.household {
            throw ServiceError.invalid("That reward isn't available.")
        }
        kid.goalRewardID = reward?.id
        try save()
    }

    func deleteReward(_ reward: Reward, by me: Member) throws {
        try requireParent(me)
        context.delete(reward)
        try save()
    }

    func requestRedemption(of reward: Reward, by me: Member) throws {
        guard !me.isParent else { throw ServiceError.notAllowed("Only kids spend points.") }
        guard reward.isActive, let household = reward.household else { throw ServiceError.invalid("That reward isn't available.") }
        guard me.available >= Int(reward.cost) else {
            throw ServiceError.invalid("You need \(Int(reward.cost) - me.available) more points for that.")
        }
        let request = try insert(Redemption.self, into: household)
        request.id = UUID()
        request.rewardTitle = reward.title
        request.rewardEmoji = reward.emoji
        request.cost = reward.cost
        request.status = .requested
        request.requestedAt = Date()
        request.member = me
        request.household = household
        try save()
    }

    /// Approving spends the points; denying leaves the balance untouched.
    func decide(_ redemption: Redemption, approve: Bool, by me: Member) throws {
        try requireParent(me)
        guard redemption.status == .requested else { throw ServiceError.invalid("This request was already decided.") }
        guard let kid = redemption.member, let household = redemption.household else { throw ServiceError.invalid("This request has no owner.") }

        if approve {
            guard kid.balance >= Int(redemption.cost) else {
                throw ServiceError.invalid("\(kid.displayName) doesn't have enough points anymore.")
            }
            let entry = try addEntry(-redemption.cost, kind: .redemption, reason: redemption.displayTitle, to: kid, in: household)
            entry.redemptionID = redemption.id
        }
        redemption.status = approve ? .approved : .denied
        redemption.decidedAt = Date()
        redemption.decidedByName = me.name
        try save()
    }

    // MARK: Helpers

    private func addEntry(_ amount: Int32, kind: EntryKind, reason: String, to kid: Member,
                          in household: Household) throws -> PointEntry {
        let entry = try insert(PointEntry.self, into: household)
        entry.id = UUID()
        entry.amount = amount
        entry.reason = reason
        entry.kind = kind
        entry.date = Date()
        entry.member = kid
        entry.household = household
        return entry
    }

    private func requireParent(_ me: Member) throws {
        guard me.isParent else { throw ServiceError.notAllowed("Only parents can do that.") }
    }

    private func make<T: NSManagedObject>(_ type: T.Type) throws -> T {
        let name = String(describing: type)
        guard let object = NSEntityDescription.insertNewObject(forEntityName: name, into: context) as? T else {
            throw ServiceError.invalid("Couldn't create a \(name). Please try again.")
        }
        return object
    }

    /// New objects must land in the same store as their household, otherwise
    /// something created by an invited person would stay out of the shared database.
    private func insert<T: NSManagedObject>(_ type: T.Type, into household: Household) throws -> T {
        let object = try make(type)
        if let store = household.objectID.persistentStore {
            context.assign(object, to: store)
        }
        return object
    }

    func save() throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
