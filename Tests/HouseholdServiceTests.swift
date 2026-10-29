import XCTest
import CoreData
@testable import HappyMama

@MainActor
final class HouseholdServiceTests: XCTestCase {
    var service: HouseholdService!
    var household: Household!
    var parent: Member!
    var kid: Member!
    var calendar: Calendar!

    override func setUp() async throws {
        let persistence = PersistenceController(mode: .inMemory)
        service = HouseholdService(persistence: persistence)
        calendar = Calendar(identifier: .gregorian)
        service.calendar = calendar
        household = try service.createHousehold(name: "Test", yourName: "Mama", emoji: "🌻", userID: "u-parent")
        parent = household.parents.first
        kid = try service.addMember(name: "Sam", role: .kid, emoji: "🦊", to: household, by: parent)
    }

    private func assignChore(points: Int = 10, recurrence: RecurrenceRule = .init(), due: Date? = nil) throws -> Chore {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Dishes"
        draft.points = points
        draft.recurrence = recurrence
        draft.dueDate = due
        return try service.createChores(draft, assignees: [kid], in: household, by: parent)[0]
    }

    // MARK: Approval gate

    func testPointsOnlyAwardedAfterParentApproves() throws {
        let chore = try assignChore(points: 25)
        XCTAssertEqual(kid.balance, 0)

        try service.markComplete(chore, by: kid, note: "done", photo: nil)
        XCTAssertEqual(chore.status, .pendingReview)
        XCTAssertEqual(kid.balance, 0, "marking done must not award points")

        try service.approve(chore, by: parent)
        XCTAssertEqual(chore.status, .approved)
        XCTAssertEqual(kid.balance, 25)
    }

    func testKidCannotApproveOwnChore() throws {
        let chore = try assignChore()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        XCTAssertThrowsError(try service.approve(chore, by: kid))
        XCTAssertEqual(kid.balance, 0)
        XCTAssertEqual(chore.status, .pendingReview)
    }

    func testCannotApproveChoreThatWasNotTurnedIn() throws {
        let chore = try assignChore()
        XCTAssertThrowsError(try service.approve(chore, by: parent))
        XCTAssertEqual(kid.balance, 0)
    }

    func testCannotApproveTwice() throws {
        let chore = try assignChore(points: 10)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        XCTAssertThrowsError(try service.approve(chore, by: parent))
        XCTAssertEqual(kid.balance, 10)
    }

    func testPartialPointsOverride() throws {
        let chore = try assignChore(points: 20)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent, points: 5)
        XCTAssertEqual(kid.balance, 5)
        XCTAssertEqual(chore.awardedPoints, 5)
    }

    func testRejectSendsBackWithNoPoints() throws {
        let chore = try assignChore()
        try service.markComplete(chore, by: kid, note: "n", photo: Data([1, 2, 3]))
        try service.reject(chore, by: parent, note: "Wipe the counter too")
        XCTAssertEqual(chore.status, .todo)
        XCTAssertTrue(chore.wasSentBack)
        XCTAssertEqual(chore.reviewNote, "Wipe the counter too")
        XCTAssertNil(chore.photo)
        XCTAssertEqual(kid.balance, 0)

        // The kid can try again and be approved.
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        XCTAssertEqual(kid.balance, 10)
    }

    func testOnlyAssigneeCanMarkComplete() throws {
        let other = try service.addMember(name: "Alex", role: .kid, emoji: "🐼", to: household, by: parent)
        let chore = try assignChore()
        XCTAssertThrowsError(try service.markComplete(chore, by: other, note: nil, photo: nil))
        XCTAssertThrowsError(try service.markComplete(chore, by: parent, note: nil, photo: nil))
    }

    func testWithdrawReturnsChoreToTodo() throws {
        let chore = try assignChore()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.withdraw(chore, by: kid)
        XCTAssertEqual(chore.status, .todo)
    }

    // MARK: Roles

    func testKidCannotCreateChores() {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Sneaky"
        XCTAssertThrowsError(try service.createChores(draft, assignees: [kid], in: household, by: kid))
    }

    func testChoresCannotBeAssignedToParents() {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Nope"
        XCTAssertThrowsError(try service.createChores(draft, assignees: [parent], in: household, by: parent))
    }

    func testAssigningToMultipleKidsCreatesACopyEach() throws {
        let other = try service.addMember(name: "Alex", role: .kid, emoji: "🐼", to: household, by: parent)
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Tidy room"
        let created = try service.createChores(draft, assignees: [kid, other], in: household, by: parent)
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(Set(created.compactMap { $0.assignee?.id }).count, 2)
    }

    func testCannotRemoveLastParentOrSelf() {
        XCTAssertThrowsError(try service.removeMember(parent, by: parent))
        XCTAssertThrowsError(try service.updateMember(parent, name: "Mama", role: .kid, emoji: "🌻", by: parent))
    }

    // MARK: Profiles

    func testClaimingParentProfileNeedsCode() throws {
        let second = try service.addMember(name: "Dad", role: .parent, emoji: "🍀", to: household, by: parent)
        XCTAssertThrowsError(try service.claim(second, userID: "u-dad", parentCode: "000000x"))
        XCTAssertThrowsError(try service.claim(second, userID: "u-dad", parentCode: nil))
        try service.claim(second, userID: "u-dad", parentCode: household.parentCode)
        XCTAssertEqual(second.appleUserID, "u-dad")
    }

    func testClaimingKidProfileNeedsNoCode() throws {
        try service.claim(kid, userID: "u-kid", parentCode: nil)
        XCTAssertEqual(kid.appleUserID, "u-kid")
        XCTAssertThrowsError(try service.claim(kid, userID: "someone-else", parentCode: nil), "already claimed")
    }

    // MARK: Rewards

    func testRedemptionSpendsPointsOnlyWhenApproved() throws {
        let chore = try assignChore(points: 60)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let reward = try service.saveReward(nil, title: "Movie night", emoji: "🎬", cost: 50, isActive: true, in: household, by: parent)

        try service.requestRedemption(of: reward, by: kid)
        XCTAssertEqual(kid.balance, 60, "requesting doesn't spend")
        XCTAssertEqual(kid.available, 10, "but it is reserved")
        XCTAssertThrowsError(try service.requestRedemption(of: reward, by: kid), "can't double-spend")

        let request = (household.redemptions as! Set<Redemption>).first!
        try service.decide(request, approve: true, by: parent)
        XCTAssertEqual(kid.balance, 10)
        XCTAssertEqual(kid.available, 10)
    }

    func testDeniedRedemptionKeepsPoints() throws {
        let chore = try assignChore(points: 60)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let reward = try service.saveReward(nil, title: "Treat", emoji: "🍦", cost: 30, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: reward, by: kid)
        let request = (household.redemptions as! Set<Redemption>).first!
        try service.decide(request, approve: false, by: parent)
        XCTAssertEqual(kid.balance, 60)
        XCTAssertEqual(kid.available, 60)
    }

    func testCannotRedeemWithoutEnoughPoints() throws {
        let reward = try service.saveReward(nil, title: "Big", emoji: "🎮", cost: 100, isActive: true, in: household, by: parent)
        XCTAssertThrowsError(try service.requestRedemption(of: reward, by: kid))
    }

    func testKidCannotDecideRedemption() throws {
        let chore = try assignChore(points: 60)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let reward = try service.saveReward(nil, title: "Treat", emoji: "🍦", cost: 30, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: reward, by: kid)
        let request = (household.redemptions as! Set<Redemption>).first!
        XCTAssertThrowsError(try service.decide(request, approve: true, by: kid))
        XCTAssertEqual(kid.balance, 60)
    }

    // MARK: Recurrence

    func testApprovingRepeatingChoreCreatesNextOne() throws {
        let today = calendar.startOfDay(for: Date())
        let chore = try assignChore(recurrence: RecurrenceRule(kind: .daily), due: today)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        XCTAssertEqual((household.chores as! Set<Chore>).count, 1, "next copy waits for approval")
        try service.approve(chore, by: parent)

        let all = (household.chores as! Set<Chore>)
        XCTAssertEqual(all.count, 2)
        let next = all.first { $0.status == .todo }!
        XCTAssertEqual(next.dueDate, calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(next.assignee, kid)
        XCTAssertEqual(next.points, chore.points)
    }

    func testNonRepeatingChoreDoesNotRespawn() throws {
        let chore = try assignChore()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        XCTAssertEqual((household.chores as! Set<Chore>).count, 1)
    }

    func testRepeatingChoreRequiresDueDate() {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Trash"
        draft.recurrence = RecurrenceRule(kind: .weekly)
        XCTAssertThrowsError(try service.createChores(draft, assignees: [kid], in: household, by: parent))
    }
}

final class RecurrenceTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testDaily() {
        XCTAssertEqual(RecurrenceRule(kind: .daily).nextDate(after: date(2026, 10, 28), calendar: calendar), date(2026, 10, 29))
    }

    func testMonthlyClampsToMonthEnd() {
        XCTAssertEqual(RecurrenceRule(kind: .monthly).nextDate(after: date(2026, 1, 31), calendar: calendar), date(2026, 2, 28))
    }

    func testWeeklyPicksNextChosenWeekday() {
        // 2026-10-28 is a Wednesday. Choose Mon (2) and Fri (6).
        var rule = RecurrenceRule(kind: .weekly)
        rule.weekdays = [2, 6]
        XCTAssertEqual(rule.nextDate(after: date(2026, 10, 28), calendar: calendar), date(2026, 10, 30), "Friday")
        XCTAssertEqual(rule.nextDate(after: date(2026, 10, 30), calendar: calendar), date(2026, 11, 2), "next Monday")
    }

    func testWeeklyWithNoDaysRepeatsEverySevenDays() {
        XCTAssertEqual(RecurrenceRule(kind: .weekly).nextDate(after: date(2026, 10, 28), calendar: calendar), date(2026, 11, 4))
    }

    func testWeekdayMaskRoundTrip() {
        var rule = RecurrenceRule(kind: .weekly)
        rule.weekdays = [1, 4, 7]
        XCTAssertEqual(rule.weekdays, [1, 4, 7])
        XCTAssertEqual(rule.weekdayMask, 0b1001001)
    }

    func testNoneNeverRepeats() {
        XCTAssertNil(RecurrenceRule(kind: .none).nextDate(after: Date(), calendar: calendar))
    }
}

@MainActor
final class DemoDataTests: XCTestCase {
    func testDemoHouseholdCoversEveryChoreState() throws {
        let service = HouseholdService(persistence: PersistenceController(mode: .inMemory))
        let household = try service.loadDemoHousehold(userID: "u-demo")

        XCTAssertEqual(household.parents.count, 2)
        XCTAssertEqual(household.kids.count, 3)
        let statuses = Set(((household.chores as? Set<Chore>) ?? []).map(\.status))
        XCTAssertTrue(statuses.isSuperset(of: [.todo, .pendingReview, .approved]))
        let ava = try XCTUnwrap(household.kids.first { $0.displayName == "Ava" })
        XCTAssertEqual(ava.balance, 10)
        XCTAssertEqual(ava.streak(calendar: service.calendar), 3)
        XCTAssertEqual(ava.goal?.displayTitle, "Movie night pick")
        XCTAssertEqual(((household.rewards as? Set<Reward>) ?? []).count, 3)
    }
}
