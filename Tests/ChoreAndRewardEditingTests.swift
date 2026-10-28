import XCTest
@testable import HappyMama

@MainActor
final class ChoreAndRewardEditingTests: ServiceTestCase {
    private func draft(_ title: String = "Vacuum", points: Int = 7, due: Date? = nil) -> HouseholdService.ChoreDraft {
        var draft = HouseholdService.ChoreDraft()
        draft.title = title
        draft.points = points
        draft.dueDate = due
        return draft
    }

    // MARK: Editing chores

    func testUpdateChoreChangesFieldsAndClearsNoteWhenReassigned() throws {
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        let chore = try assign()
        chore.reviewNote = "Try again"

        var edit = draft("  Vacuum stairs ", points: -4)
        edit.notes = "  Every step "
        try service.updateChore(chore, with: edit, assignee: other, by: parent)

        XCTAssertEqual(chore.title, "Vacuum stairs")
        XCTAssertEqual(chore.notes, "Every step")
        XCTAssertEqual(chore.points, 0, "negative points are clamped to zero")
        XCTAssertEqual(chore.assignee?.id, other.id)
        XCTAssertNil(chore.reviewNote)
    }

    func testUpdateChoreKeepsNoteWhenAssigneeUnchanged() throws {
        let chore = try assign()
        chore.reviewNote = "Corners too"
        try service.updateChore(chore, with: draft(), assignee: kid, by: parent)
        XCTAssertEqual(chore.reviewNote, "Corners too")
    }

    func testUpdateChoreStoresStartOfDayDueDateAndRecurrence() throws {
        let chore = try assign()
        var edit = draft(due: Date(timeIntervalSince1970: 1_800_000_123))
        edit.recurrence.kind = .daily
        try service.updateChore(chore, with: edit, assignee: kid, by: parent)

        XCTAssertEqual(chore.dueDate, calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_123)))
        XCTAssertEqual(chore.recurrence.kind, .daily)
    }

    func testUpdateChoreValidation() throws {
        let chore = try assign()
        assertThrowsServiceError(try service.updateChore(chore, with: draft(" "), assignee: kid, by: parent))
        assertThrowsServiceError(try service.updateChore(chore, with: draft(), assignee: parent, by: parent))
        assertThrowsServiceError(try service.updateChore(chore, with: draft(), assignee: kid, by: kid))

        var repeating = draft()
        repeating.recurrence.kind = .weekly
        assertThrowsServiceError(try service.updateChore(chore, with: repeating, assignee: kid, by: parent))
    }

    func testCannotEditAChoreThatWasTurnedIn() throws {
        let chore = try assign()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        assertThrowsServiceError(try service.updateChore(chore, with: draft(), assignee: kid, by: parent))
    }

    func testDeleteChoreIsParentOnly() throws {
        let chore = try assign()
        assertThrowsServiceError(try service.deleteChore(chore, by: kid))
        XCTAssertEqual((household.chores as? Set<Chore>)?.count, 1)

        try service.deleteChore(chore, by: parent)
        XCTAssertEqual((household.chores as? Set<Chore>)?.count, 0)
    }

    // MARK: Turning in

    func testMarkCompleteKeepsNoteAndPhotoAndDropsBlankNote() throws {
        let chore = try assign()
        try service.markComplete(chore, by: kid, note: "   ", photo: Data([1, 2, 3]))
        XCTAssertNil(chore.completionNote)
        XCTAssertEqual(chore.photo, Data([1, 2, 3]))
        XCTAssertNotNil(chore.completedAt)

        try service.withdraw(chore, by: kid)
        XCTAssertNil(chore.photo)
        XCTAssertNil(chore.completedAt)
    }

    func testParentCannotMarkAChoreDoneOrWithdrawForAKid() throws {
        let chore = try assign()
        assertThrowsServiceError(try service.markComplete(chore, by: parent, note: nil, photo: nil))
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        assertThrowsServiceError(try service.markComplete(chore, by: kid, note: nil, photo: nil))
        assertThrowsServiceError(try service.withdraw(chore, by: parent))
    }

    func testRejectWithBlankNoteUsesDefaultAndClearsSubmission() throws {
        let chore = try assign()
        try service.markComplete(chore, by: kid, note: "done", photo: Data([9]))
        try service.reject(chore, by: parent, note: "  ")

        XCTAssertEqual(chore.reviewNote, "Please take another look.")
        XCTAssertTrue(chore.wasSentBack)
        XCTAssertNil(chore.photo)
        XCTAssertNil(chore.completionNote)
        XCTAssertEqual(chore.reviewedByName, "Mama")
    }

    func testRejectRequiresAParentAndATurnedInChore() throws {
        let chore = try assign()
        assertThrowsServiceError(try service.reject(chore, by: parent, note: "no"))
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        assertThrowsServiceError(try service.reject(chore, by: kid, note: "no"))
    }

    // MARK: Recurrence on approval

    func testLateRepeatingChoreRestartsFromToday() throws {
        let today = calendar.startOfDay(for: Date())
        let lastWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: today))
        var rule = RecurrenceRule()
        rule.kind = .daily
        let chore = try assign(due: lastWeek, recurrence: rule)

        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)

        let chores = (household.chores as? Set<Chore>) ?? []
        let next = try XCTUnwrap(chores.first { $0.status == .todo })
        XCTAssertEqual(next.dueDate, calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(next.assignee?.id, kid.id)
        XCTAssertEqual(next.recurrence.kind, .daily)
    }

    func testApprovingWithZeroOrNegativeOverrideAwardsNothing() throws {
        let chore = try assign(points: 10)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent, points: -5)
        XCTAssertEqual(chore.awardedPoints, 0)
        XCTAssertEqual(kid.balance, 0)
    }

    // MARK: Rewards

    func testSaveRewardValidatesAndDefaultsEmoji() throws {
        assertThrowsServiceError(try service.saveReward(nil, title: " ", emoji: "🍦", cost: 5, isActive: true, in: household, by: parent))
        assertThrowsServiceError(try service.saveReward(nil, title: "Ice cream", emoji: "🍦", cost: 0, isActive: true, in: household, by: parent))
        assertThrowsServiceError(try service.saveReward(nil, title: "Ice cream", emoji: "🍦", cost: 5, isActive: true, in: household, by: kid))

        let reward = try service.saveReward(nil, title: " Ice cream ", emoji: " ", cost: 5, isActive: true, in: household, by: parent)
        XCTAssertEqual(reward.title, "Ice cream")
        XCTAssertEqual(reward.emoji, "🎁")
    }

    func testEditingARewardUpdatesItInPlace() throws {
        let reward = try service.saveReward(nil, title: "Movie", emoji: "🎬", cost: 20, isActive: true, in: household, by: parent)
        let edited = try service.saveReward(reward, title: "Movie night", emoji: "🍿", cost: 25, isActive: false, in: household, by: parent)

        XCTAssertTrue(edited === reward)
        XCTAssertEqual(reward.cost, 25)
        XCTAssertFalse(reward.isActive)
        XCTAssertEqual((household.rewards as? Set<Reward>)?.count, 1)
    }

    func testDeleteRewardIsParentOnly() throws {
        let reward = try service.saveReward(nil, title: "Movie", emoji: "🎬", cost: 20, isActive: true, in: household, by: parent)
        assertThrowsServiceError(try service.deleteReward(reward, by: kid))
        try service.deleteReward(reward, by: parent)
        XCTAssertEqual((household.rewards as? Set<Reward>)?.count, 0)
    }

    func testInactiveRewardCannotBeRequested() throws {
        let reward = try service.saveReward(nil, title: "Movie", emoji: "🎬", cost: 1, isActive: false, in: household, by: parent)
        assertThrowsServiceError(try service.requestRedemption(of: reward, by: kid))
    }

    func testParentsCannotRequestRewards() throws {
        let reward = try service.saveReward(nil, title: "Movie", emoji: "🎬", cost: 1, isActive: true, in: household, by: parent)
        assertThrowsServiceError(try service.requestRedemption(of: reward, by: parent))
    }

    func testPendingRequestReservesPointsUntilDecided() throws {
        let chore = try assign(points: 10)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let reward = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 4, isActive: true, in: household, by: parent)

        try service.requestRedemption(of: reward, by: kid)
        XCTAssertEqual(kid.balance, 10)
        XCTAssertEqual(kid.reserved, 4)
        XCTAssertEqual(kid.available, 6)

        let request = try XCTUnwrap((household.redemptions as? Set<Redemption>)?.first)
        try service.decide(request, approve: false, by: parent)
        XCTAssertEqual(kid.reserved, 0)
        XCTAssertEqual(kid.available, 10)
        assertThrowsServiceError(try service.decide(request, approve: true, by: parent))
    }
}
