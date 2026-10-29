import XCTest
@testable import HappyMama

@MainActor
final class DueTimeTests: ServiceTestCase {
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func at(_ hour: Int, _ minute: Int = 0, daysFromToday days: Int = 0) throws -> Date {
        let day = try XCTUnwrap(calendar.date(byAdding: .day, value: days, to: today))
        return try XCTUnwrap(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day))
    }

    private func chore(due: Date?, time: Int?, recurrence: RecurrenceRule = .init()) throws -> Chore {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Dishes"
        draft.points = 6
        draft.dueDate = due
        draft.dueTime = time
        draft.recurrence = recurrence
        return try service.createChores(draft, assignees: [kid], in: household, by: parent)[0]
    }

    func testDueTimeIsStoredAndDroppedWithoutADate() throws {
        let timed = try chore(due: today, time: 17 * 60)
        XCTAssertEqual(timed.dueTime, 17 * 60)
        XCTAssertEqual(timed.dueAt(calendar: calendar), try at(17))

        let undated = try chore(due: nil, time: 17 * 60)
        XCTAssertNil(undated.dueTime, "a time means nothing without a day")
        XCTAssertNil(undated.dueAt(calendar: calendar))
    }

    func testWithoutATimeItsDueByTheEndOfTheDay() throws {
        let plain = try chore(due: today, time: nil)
        XCTAssertNil(plain.dueTime)
        XCTAssertEqual(plain.dueAt(calendar: calendar), try at(0, daysFromToday: 1))
        XCTAssertFalse(plain.isOverdue(now: try at(23, 59), calendar: calendar))
        XCTAssertTrue(plain.isOverdue(now: try at(0, 1, daysFromToday: 1), calendar: calendar))
    }

    func testATimedChoreIsOverdueOnceTheTimePasses() throws {
        let timed = try chore(due: today, time: 17 * 60)
        XCTAssertFalse(timed.isOverdue(now: try at(16, 59), calendar: calendar))
        XCTAssertTrue(timed.isOverdue(now: try at(17, 1), calendar: calendar))
        try service.markComplete(timed, by: kid, note: nil, photo: nil)
        XCTAssertFalse(timed.isOverdue(now: try at(18), calendar: calendar), "turned in isn't overdue")
    }

    func testOutOfRangeTimesAreClamped() throws {
        let timed = try chore(due: today, time: 17 * 60)
        timed.dueTime = 9_999
        XCTAssertEqual(timed.dueTime, 24 * 60 - 1)
        timed.dueTime = -5
        XCTAssertEqual(timed.dueTime, 0)
        timed.dueTime = nil
        XCTAssertEqual(timed.dueMinute, -1)
    }

    func testEditingCanAddAndRemoveATime() throws {
        let plain = try chore(due: today, time: nil)
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Dishes"
        draft.dueDate = today
        draft.dueTime = 8 * 60 + 30
        try service.updateChore(plain, with: draft, assignee: kid, by: parent)
        XCTAssertEqual(plain.dueTime, 510)
        draft.dueTime = nil
        try service.updateChore(plain, with: draft, assignee: kid, by: parent)
        XCTAssertNil(plain.dueTime)
    }

    func testRepeatingCopiesKeepTheTime() throws {
        var daily = RecurrenceRule()
        daily.kind = .daily
        let first = try chore(due: today, time: 7 * 60, recurrence: daily)
        try service.markComplete(first, by: kid, note: nil, photo: nil)
        try service.approve(first, by: parent)
        let next = try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == first.id })
        XCTAssertEqual(next.dueTime, 7 * 60)
    }

    func testReminderComesAnHourBeforeTheTime() throws {
        _ = try chore(due: today, time: 17 * 60)
        let reminders = Notifier.dueReminders(household: household, me: kid, now: try at(12), calendar: calendar)
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.title, "Due soon: Dishes")
        XCTAssertEqual(reminders.first?.fireAt.hour, 16)
        XCTAssertEqual(reminders.first?.fireAt.minute, 0)
        XCTAssertTrue(reminders.first?.body.hasSuffix("Worth 6 points.") == true)

        XCTAssertTrue(Notifier.dueReminders(household: household, me: kid, now: try at(16, 30), calendar: calendar).isEmpty,
                      "the warning time has passed")
    }

    func testEarlyMorningTimesAreRemindedAtMidnightNotTheDayBefore() throws {
        _ = try chore(due: try at(0, daysFromToday: 1), time: 30)
        let reminder = try XCTUnwrap(Notifier.dueReminders(household: household, me: kid, now: try at(12), calendar: calendar).first)
        XCTAssertEqual(reminder.fireAt.hour, 0)
        XCTAssertEqual(reminder.fireAt.minute, 0)
    }

    func testWidgetSnapshotSortsByTimeAndCarriesIt() throws {
        _ = try chore(due: today, time: nil)
        let early = try chore(due: today, time: 8 * 60)
        early.title = "Early"
        let snap = WidgetSnapshot(household: household, me: kid, now: Date(), calendar: calendar)
        XCTAssertEqual(snap.kids[0].open.map(\.title), ["Early", "Dishes"])
        XCTAssertEqual(snap.kids[0].open.first?.dueTime, 8 * 60)
    }
}
