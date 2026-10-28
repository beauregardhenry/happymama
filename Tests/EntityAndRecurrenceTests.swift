import XCTest
@testable import HappyMama

@MainActor
final class EntityTests: ServiceTestCase {
    func testChoreOverdueOnlyWhenOpenAndPastDue() throws {
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        let late = try assign(due: yesterday)
        XCTAssertTrue(late.isOverdue)
        XCTAssertFalse(try assign(due: today).isOverdue, "due today is not overdue")
        XCTAssertFalse(try assign(due: tomorrow).isOverdue)
        XCTAssertFalse(try assign().isOverdue, "no due date is never overdue")

        try service.markComplete(late, by: kid, note: nil, photo: nil)
        XCTAssertFalse(late.isOverdue, "turned-in chores are not overdue")
    }

    func testWasSentBackNeedsTodoStatusAndANote() throws {
        let chore = try assign()
        XCTAssertFalse(chore.wasSentBack)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.reject(chore, by: parent, note: "Again")
        XCTAssertTrue(chore.wasSentBack)

        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        XCTAssertFalse(chore.wasSentBack)
    }

    func testBalanceSumsEarningsAndSpending() throws {
        let chore = try assign(points: 12)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let reward = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 5, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: reward, by: kid)
        let request = try XCTUnwrap((household.redemptions as? Set<Redemption>)?.first)
        try service.decide(request, approve: true, by: parent)

        XCTAssertEqual(kid.balance, 7)
        XCTAssertEqual(kid.reserved, 0)
        XCTAssertEqual(kid.entryList.count, 2)
        XCTAssertEqual(kid.entryList.map(\.kind).filter { $0 == .redemption }.count, 1)
    }

    func testDisplayFallbacksForMissingValues() throws {
        let context = service.context
        let chore = Chore(context: context)
        XCTAssertEqual(chore.displayTitle, "Chore")
        XCTAssertEqual(chore.status, .todo)

        chore.statusRaw = "nonsense"
        XCTAssertEqual(chore.status, .todo, "unknown status falls back to todo")

        let reward = Reward(context: context)
        XCTAssertEqual(reward.displayTitle, "Reward")
        XCTAssertEqual(reward.displayEmoji, "🎁")

        let redemption = Redemption(context: context)
        XCTAssertEqual(redemption.displayTitle, "Reward")
        XCTAssertEqual(redemption.displayEmoji, "🎁")
        XCTAssertEqual(redemption.status, .requested)

        let entry = PointEntry(context: context)
        XCTAssertEqual(entry.kind, .chore)

        let member = Member(context: context)
        XCTAssertEqual(member.displayName, "Someone")
        XCTAssertEqual(member.displayEmoji, "🦊")
        member.role = .parent
        XCTAssertEqual(member.displayEmoji, "🌻")

        XCTAssertEqual(Household(context: context).displayName, "Our Household")
        context.rollback()
    }

    func testRoleTitles() {
        XCTAssertEqual(Role.parent.title, "Parent")
        XCTAssertEqual(Role.kid.title, "Kid")
    }
}

final class RecurrenceSummaryTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testSummaries() {
        var rule = RecurrenceRule()
        XCTAssertEqual(rule.summary(calendar: calendar), "Doesn't repeat")
        rule.kind = .daily
        XCTAssertEqual(rule.summary(calendar: calendar), "Every day")
        rule.kind = .monthly
        XCTAssertEqual(rule.summary(calendar: calendar), "Every month")
        rule.kind = .weekly
        XCTAssertEqual(rule.summary(calendar: calendar), "Every week")
    }

    func testWeeklySummaryListsChosenDaysInOrder() {
        var rule = RecurrenceRule(kind: .weekly)
        rule.weekdays = [6, 2]
        let names = calendar.shortWeekdaySymbols
        XCTAssertEqual(rule.summary(calendar: calendar), "Every \(names[1]), \(names[5])")
    }

    func testTitlesAreHumanReadable() {
        XCTAssertEqual(Recurrence.allCases.map(\.title), ["Never", "Every day", "Every week", "Every month"])
        XCTAssertEqual(Recurrence.weekly.id, "weekly")
    }

    func testIsRepeating() {
        XCTAssertFalse(RecurrenceRule().isRepeating)
        XCTAssertTrue(RecurrenceRule(kind: .monthly).isRepeating)
    }
}
