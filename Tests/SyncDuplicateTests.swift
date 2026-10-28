import XCTest
import CoreData
@testable import HappyMama

/// Two parents acting on the same chore or request from different devices before
/// either syncs. Each device records its own entry; these tests add the copy the
/// other device would have made and check it counts once and gets cleaned up.
@MainActor
final class SyncDuplicateTests: ServiceTestCase {
    private var entries: Set<PointEntry> { (household.entries as? Set<PointEntry>) ?? [] }
    private var chores: Set<Chore> { (household.chores as? Set<Chore>) ?? [] }

    /// The entry the other parent's device would have written for the same source.
    @discardableResult
    private func otherDeviceCopy(of entry: PointEntry) -> PointEntry {
        let copy = PointEntry(context: service.context)
        copy.id = UUID()
        copy.amount = entry.amount
        copy.reason = entry.reason
        copy.kind = entry.kind
        copy.date = Date()
        copy.choreID = entry.choreID
        copy.redemptionID = entry.redemptionID
        copy.member = entry.member
        copy.household = household
        return copy
    }

    private func approvedChore(points: Int = 10, recurrence: RecurrenceRule = .init(), due: Date? = nil) throws -> Chore {
        let chore = try assign(points: points, due: due, recurrence: recurrence)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        return chore
    }

    func testApprovalRecordsWhichChoreItPaysFor() throws {
        let chore = try approvedChore()
        XCTAssertEqual(entries.first?.choreID, chore.id)
    }

    func testDoubleApprovalAwardsOnceAndCleanupKeepsOneEntry() throws {
        _ = try approvedChore(points: 10)
        let original = try XCTUnwrap(entries.first)
        otherDeviceCopy(of: original)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(kid.balance, 10, "the duplicate must not count before cleanup runs")
        XCTAssertEqual(kid.entryList.count, 1)

        try service.resolveSyncDuplicates(in: household)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(kid.balance, 10)
    }

    func testCleanupKeepsTheSameEntryOnEveryDevice() throws {
        _ = try approvedChore()
        otherDeviceCopy(of: try XCTUnwrap(entries.first))
        let lowest = entries.compactMap(\.id).map(\.uuidString).min()

        try service.resolveSyncDuplicates(in: household)
        XCTAssertEqual(entries.first?.id?.uuidString, lowest)
    }

    func testDoubleRewardApprovalSpendsOnce() throws {
        _ = try approvedChore(points: 20)
        let reward = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 5, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: reward, by: kid)
        let request = try XCTUnwrap((household.redemptions as? Set<Redemption>)?.first)
        try service.decide(request, approve: true, by: parent)

        let spend = try XCTUnwrap(entries.first { $0.kind == .redemption })
        XCTAssertEqual(spend.redemptionID, request.id)
        otherDeviceCopy(of: spend)
        XCTAssertEqual(kid.balance, 15)

        try service.resolveSyncDuplicates(in: household)
        XCTAssertEqual(entries.filter { $0.kind == .redemption }.count, 1)
        XCTAssertEqual(kid.balance, 15)
    }

    func testDifferentChoresBothCount() throws {
        _ = try approvedChore(points: 10)
        _ = try approvedChore(points: 5)
        try service.resolveSyncDuplicates(in: household)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(kid.balance, 15)
    }

    func testEntriesWithoutASourceAreNeverMerged() throws {
        for amount in [3, 4] {
            let entry = PointEntry(context: service.context)
            entry.id = UUID()
            entry.amount = Int32(amount)
            entry.kind = .chore
            entry.member = kid
            entry.household = household
        }
        XCTAssertEqual(kid.balance, 7)
        try service.resolveSyncDuplicates(in: household)
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: Repeating chores

    private func daily() -> RecurrenceRule {
        var rule = RecurrenceRule()
        rule.kind = .daily
        return rule
    }

    /// The next copy the other parent's device would have spawned.
    @discardableResult
    private func otherDeviceCopy(of chore: Chore) -> Chore {
        let copy = Chore(context: service.context)
        copy.id = UUID()
        copy.title = chore.title
        copy.points = chore.points
        copy.status = .todo
        copy.dueDate = chore.dueDate
        copy.recurrence = chore.recurrence
        copy.sourceChoreID = chore.sourceChoreID
        copy.assignee = chore.assignee
        copy.household = household
        return copy
    }

    func testNextCopyRemembersWhereItCameFrom() throws {
        let chore = try approvedChore(recurrence: daily(), due: Date())
        let next = try XCTUnwrap(chores.first { $0.status == .todo })
        XCTAssertEqual(next.sourceChoreID, chore.id)
    }

    func testDuplicateNextCopyIsRemoved() throws {
        _ = try approvedChore(recurrence: daily(), due: Date())
        let next = try XCTUnwrap(chores.first { $0.status == .todo })
        otherDeviceCopy(of: next)
        XCTAssertEqual(chores.filter { $0.status == .todo }.count, 2)

        try service.resolveSyncDuplicates(in: household)
        XCTAssertEqual(chores.filter { $0.status == .todo }.count, 1)
        XCTAssertEqual(chores.count, 2, "the approved original stays")
    }

    func testCleanupKeepsTheCopyTheKidAlreadyTurnedIn() throws {
        _ = try approvedChore(recurrence: daily(), due: Date())
        let next = try XCTUnwrap(chores.first { $0.status == .todo })
        let duplicate = otherDeviceCopy(of: next)
        try service.markComplete(duplicate, by: kid, note: "done", photo: nil)

        try service.resolveSyncDuplicates(in: household)
        let copies = chores.filter { $0.sourceChoreID != nil }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(copies.first?.status, .pendingReview)
    }

    func testCleanupWithNothingToFixChangesNothing() throws {
        _ = try approvedChore(recurrence: daily(), due: Date())
        try service.resolveSyncDuplicates(in: household)
        XCTAssertFalse(service.context.hasChanges)
        XCTAssertEqual(chores.count, 2)
        XCTAssertEqual(entries.count, 1)
    }
}

@MainActor
final class DueReminderTests: ServiceTestCase {
    private func at(_ hour: Int, daysFromToday days: Int = 0) throws -> Date {
        let today = calendar.startOfDay(for: Date())
        let day = try XCTUnwrap(calendar.date(byAdding: .day, value: days, to: today))
        return try XCTUnwrap(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day))
    }

    private func reminderTitles(for member: Member, now: Date) -> [String] {
        Notifier.dueReminders(household: household, me: member, now: now, calendar: calendar).map(\.title).sorted()
    }

    func testKidIsRemindedAtNineOnTheDueDate() throws {
        let chore = try assign(title: "Dishes", points: 6, due: try at(0, daysFromToday: 1))
        let reminders = Notifier.dueReminders(household: household, me: kid, now: try at(12), calendar: calendar)

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.id, "due-\(try XCTUnwrap(chore.id).uuidString)")
        XCTAssertEqual(reminders.first?.title, "Due today: Dishes")
        XCTAssertEqual(reminders.first?.body, "Worth 6 points.")
        XCTAssertEqual(reminders.first?.fireAt.hour, 9)
    }

    func testReminderForTodayOnlyBeforeNine() throws {
        _ = try assign(title: "Today", due: try at(0))
        XCTAssertEqual(reminderTitles(for: kid, now: try at(8)), ["Due today: Today"])
        XCTAssertEqual(reminderTitles(for: kid, now: try at(10)), [])
    }

    func testNoRemindersForPastUndatedTurnedInOrOtherKidsChores() throws {
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        _ = try assign(title: "Late", due: try at(0, daysFromToday: -2))
        _ = try assign(title: "Whenever")
        _ = try assign(title: "Pip's", to: other, due: try at(0, daysFromToday: 1))
        let done = try assign(title: "Done", due: try at(0, daysFromToday: 1))
        try service.markComplete(done, by: kid, note: nil, photo: nil)
        _ = try assign(title: "Mine", due: try at(0, daysFromToday: 3))

        XCTAssertEqual(reminderTitles(for: kid, now: try at(12)), ["Due today: Mine"])
        XCTAssertEqual(reminderTitles(for: other, now: try at(12)), ["Due today: Pip's"])
    }

    func testParentsGetNoReminders() throws {
        _ = try assign(due: try at(0, daysFromToday: 1))
        XCTAssertEqual(reminderTitles(for: parent, now: try at(12)), [])
    }

    func testOverdueUsesTheGivenCalendarAndTime() throws {
        let chore = try assign(due: try at(0))
        XCTAssertFalse(chore.isOverdue(now: try at(23), calendar: calendar))
        XCTAssertTrue(chore.isOverdue(now: try at(1, daysFromToday: 1), calendar: calendar))
    }
}

@MainActor
final class MemberRemovalTests: ServiceTestCase {
    func testRemovingAKidRemovesTheirChoresPointsAndRequests() throws {
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        let chore = try assign(points: 10)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        _ = try assign(title: "Open")
        _ = try assign(title: "Pip's", to: other)
        let reward = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 3, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: reward, by: kid)

        try service.removeMember(kid, by: parent)

        let chores = (household.chores as? Set<Chore>) ?? []
        XCTAssertEqual(chores.map(\.displayTitle), ["Pip's"])
        XCTAssertEqual((household.entries as? Set<PointEntry>)?.count, 0)
        XCTAssertEqual((household.redemptions as? Set<Redemption>)?.count, 0)
        XCTAssertEqual((household.rewards as? Set<Reward>)?.count, 1, "rewards belong to the household")
    }
}
