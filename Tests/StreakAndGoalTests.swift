import XCTest
@testable import HappyMama

@MainActor
final class StreakTests: ServiceTestCase {
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func day(_ offset: Int, hour: Int = 18) throws -> Date {
        let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: today))
        return try XCTUnwrap(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date))
    }

    /// A chore the kid turned in on the given day, approved unless `approve` is false.
    private func turnedIn(daysAgo: Int, approve: Bool = true) throws {
        let chore = try assign()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        chore.completedAt = try day(-daysAgo)
        if approve { try service.approve(chore, by: parent) }
    }

    private var streak: Int { kid.streak(now: (try? day(0, hour: 12)) ?? Date(), calendar: calendar) }

    func testNoChoresNoStreak() {
        XCTAssertEqual(streak, 0)
    }

    func testConsecutiveDaysEndingTodayCount() throws {
        for daysAgo in [0, 1, 2] { try turnedIn(daysAgo: daysAgo) }
        XCTAssertEqual(streak, 3)
    }

    func testStreakEndingYesterdayStillCounts() throws {
        for daysAgo in [1, 2] { try turnedIn(daysAgo: daysAgo) }
        XCTAssertEqual(streak, 2)
    }

    func testAMissedDayBreaksTheStreak() throws {
        for daysAgo in [0, 2, 3, 4] { try turnedIn(daysAgo: daysAgo) }
        XCTAssertEqual(streak, 1)
        XCTAssertEqual(kid.streak(now: try day(-2, hour: 12), calendar: calendar), 3)
    }

    func testTwoDaysAgoIsTooLate() throws {
        try turnedIn(daysAgo: 2)
        XCTAssertEqual(streak, 0)
    }

    func testSeveralChoresOnOneDayCountOnce() throws {
        try turnedIn(daysAgo: 0)
        try turnedIn(daysAgo: 0)
        XCTAssertEqual(streak, 1)
    }

    func testWaitingForApprovalCountsButSentBackDoesNot() throws {
        try turnedIn(daysAgo: 0, approve: false)
        XCTAssertEqual(streak, 1, "turning it in is what counts")

        let chore = try assign()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        chore.completedAt = try day(-1)
        try service.reject(chore, by: parent, note: "Again please")
        XCTAssertEqual(streak, 1)
    }
}

@MainActor
final class SavingsGoalTests: ServiceTestCase {
    private func reward(cost: Int = 20, active: Bool = true) throws -> Reward {
        try service.saveReward(nil, title: "Movie", emoji: "🎬", cost: cost, isActive: active, in: household, by: parent)
    }

    private func earn(_ points: Int) throws {
        let chore = try assign(points: points)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
    }

    func testKidPicksAGoalAndSeesProgress() throws {
        let movie = try reward(cost: 20)
        try service.setGoal(movie, for: kid, by: kid)
        XCTAssertEqual(kid.goal?.id, movie.id)
        XCTAssertEqual(kid.goalProgress, 0)

        try earn(5)
        XCTAssertEqual(kid.goalProgress, 0.25, accuracy: 0.001)
        try earn(30)
        XCTAssertEqual(kid.goalProgress, 1, "progress stops at the goal")
    }

    func testPointsOnHoldDontCountTowardTheGoal() throws {
        let movie = try reward(cost: 20)
        let treat = try reward(cost: 5)
        try earn(10)
        try service.setGoal(movie, for: kid, by: kid)
        try service.requestRedemption(of: treat, by: kid)
        XCTAssertEqual(kid.goalProgress, 0.25, accuracy: 0.001)
    }

    func testParentsCanSetAndClearAKidsGoal() throws {
        let movie = try reward()
        try service.setGoal(movie, for: kid, by: parent)
        XCTAssertEqual(kid.goal?.id, movie.id)
        try service.setGoal(nil, for: kid, by: parent)
        XCTAssertNil(kid.goal)
        XCTAssertEqual(kid.goalProgress, 0)
    }

    func testGoalRules() throws {
        let movie = try reward()
        let hidden = try reward(active: false)
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)

        assertThrowsServiceError(try service.setGoal(movie, for: parent, by: parent))
        assertThrowsServiceError(try service.setGoal(movie, for: other, by: kid))
        assertThrowsServiceError(try service.setGoal(hidden, for: kid, by: kid))
        XCTAssertNil(kid.goalRewardID)
    }

    func testHidingOrDeletingTheRewardClearsTheGoal() throws {
        let movie = try reward()
        try service.setGoal(movie, for: kid, by: kid)
        try service.saveReward(movie, title: "Movie", emoji: "🎬", cost: 20, isActive: false, in: household, by: parent)
        XCTAssertNil(kid.goal)

        try service.saveReward(movie, title: "Movie", emoji: "🎬", cost: 20, isActive: true, in: household, by: parent)
        XCTAssertEqual(kid.goal?.id, movie.id, "it comes back if the reward does")
        try service.deleteReward(movie, by: parent)
        XCTAssertNil(kid.goal)
    }
}
