import XCTest
@testable import HappyMama

@MainActor
final class AutoApproveTests: ServiceTestCase {
    private func habit(points: Int = 2, auto: Bool = true, daily: Bool = false) throws -> Chore {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Brush teeth"
        draft.points = points
        draft.autoApprove = auto
        if daily {
            draft.recurrence.kind = .daily
            draft.dueDate = Date()
        }
        return try service.createChores(draft, assignees: [kid], in: household, by: parent)[0]
    }

    func testMarkingDoneAwardsThePointsRightAway() throws {
        let chore = try habit(points: 2)
        try service.markComplete(chore, by: kid, note: "Done", photo: nil)

        XCTAssertEqual(chore.status, .approved)
        XCTAssertEqual(chore.awardedPoints, 2)
        XCTAssertEqual(kid.balance, 2)
        XCTAssertNil(chore.reviewedByName, "nobody reviewed it")
        XCTAssertNotNil(chore.reviewedAt)
        XCTAssertEqual(chore.completionNote, "Done")
        XCTAssertEqual(kid.entryList.first?.choreID, chore.id)
    }

    func testOrdinaryChoresStillWaitForAParent() throws {
        let chore = try habit(auto: false)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        XCTAssertEqual(chore.status, .pendingReview)
        XCTAssertEqual(kid.balance, 0)
    }

    func testRepeatingHabitComesBackStillAutomatic() throws {
        let chore = try habit(daily: true)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        let next = try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == chore.id })
        XCTAssertTrue(next.autoApprove)
        XCTAssertEqual(next.status, .todo)
    }

    func testParentsDontSeeItInReviewButTheKidHearsAboutIt() throws {
        let chore = try habit()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        let notifier = Notifier()
        XCTAssertTrue(notifier.events(household: household, me: parent).isEmpty)
        XCTAssertEqual(notifier.events(household: household, me: kid).map(\.title), ["You earned 2 points!"])
    }

    func testItCountsTowardTheStreak() throws {
        let chore = try habit()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        XCTAssertEqual(kid.streak(calendar: calendar), 1)
    }

    func testEditingCanTurnItOnAndOff() throws {
        let chore = try habit(auto: false)
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Brush teeth"
        draft.autoApprove = true
        try service.updateChore(chore, with: draft, assignee: kid, by: parent)
        XCTAssertTrue(chore.autoApprove)
        draft.autoApprove = false
        try service.updateChore(chore, with: draft, assignee: kid, by: parent)
        XCTAssertFalse(chore.autoApprove)
    }

    func testOnlyTheKidCanMarkItDone() throws {
        let chore = try habit()
        assertThrowsServiceError(try service.markComplete(chore, by: parent, note: nil, photo: nil))
        XCTAssertEqual(kid.balance, 0)
    }
}
