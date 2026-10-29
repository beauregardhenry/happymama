import XCTest
@testable import HappyMama

@MainActor
final class RotationTests: ServiceTestCase {
    private var ben: Member!
    private var cleo: Member!

    override func setUp() async throws {
        try await super.setUp()
        ben = try service.addMember(name: "Ben", role: .kid, emoji: "🐼", to: household, by: parent)
        cleo = try service.addMember(name: "Cleo", role: .kid, emoji: "🐯", to: household, by: parent)
    }

    private func turns(_ kids: [Member], recurrence: Recurrence = .daily) -> HouseholdService.ChoreDraft {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Dishes"
        draft.points = 5
        draft.dueDate = Date()
        draft.recurrence.kind = recurrence
        draft.takeTurns = true
        return draft
    }

    private func rotating(_ kids: [Member]) throws -> Chore {
        let created = try service.createChores(turns(kids), assignees: kids, in: household, by: parent)
        XCTAssertEqual(created.count, 1, "taking turns makes one chore, not a copy each")
        return created[0]
    }

    /// Turns in and approves the open copy, returning the next one.
    private func finish(_ chore: Chore) throws -> Chore {
        let kid = try XCTUnwrap(chore.assignee)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        return try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == chore.id })
    }

    func testFirstKidStartsAndEveryoneGetsATurnInOrder() throws {
        var chore = try rotating([kid, ben, cleo])
        XCTAssertEqual(chore.assignee, kid)
        XCTAssertTrue(chore.takesTurns)
        XCTAssertEqual(chore.nextAssignee, ben)

        var order: [String] = [try XCTUnwrap(chore.assignee).displayName]
        for _ in 0..<3 {
            chore = try finish(chore)
            order.append(try XCTUnwrap(chore.assignee).displayName)
        }
        XCTAssertEqual(order, ["Sam", "Ben", "Cleo", "Sam"])
        XCTAssertTrue(chore.takesTurns, "each copy keeps the rotation")
    }

    func testPointsGoToWhoeverDidIt() throws {
        let chore = try rotating([kid, ben])
        let next = try finish(chore)
        _ = try finish(next)
        XCTAssertEqual(kid.balance, 5)
        XCTAssertEqual(ben.balance, 5)
    }

    func testTakingTurnsRules() throws {
        assertThrowsServiceError(try service.createChores(turns([kid]), assignees: [kid], in: household, by: parent))
        assertThrowsServiceError(try service.createChores(turns([kid, ben], recurrence: .none), assignees: [kid, ben],
                                                          in: household, by: parent))
        XCTAssertEqual((household.chores as? Set<Chore>)?.count, 0)
    }

    func testCopiesStillWorkWithoutTakingTurns() throws {
        var draft = turns([kid, ben])
        draft.takeTurns = false
        let created = try service.createChores(draft, assignees: [kid, ben], in: household, by: parent)
        XCTAssertEqual(created.count, 2)
        XCTAssertFalse(created.contains(where: \.takesTurns))
        XCTAssertEqual(try finish(created[0]).assignee, created[0].assignee, "a plain repeating chore stays with its kid")
    }

    func testEditingTheRotationKeepsWhoseTurnItIs() throws {
        let chore = try rotating([kid, ben])
        try service.updateChore(chore, with: turns([]), assignees: [ben, kid, cleo], by: parent)
        XCTAssertEqual(chore.assignee, kid)
        XCTAssertEqual(chore.rotation, [ben, kid, cleo])
        XCTAssertEqual(chore.nextAssignee, cleo)

        try service.updateChore(chore, with: turns([]), assignees: [ben, cleo], by: parent)
        XCTAssertEqual(chore.assignee, ben, "Sam left the rotation, so it moves to the first kid")
    }

    func testTurningTurnsOffGivesItToOneKid() throws {
        let chore = try rotating([kid, ben])
        var plain = turns([])
        plain.takeTurns = false
        assertThrowsServiceError(try service.updateChore(chore, with: plain, assignees: [kid, ben], by: parent))

        try service.updateChore(chore, with: plain, assignees: [kid], by: parent)
        XCTAssertFalse(chore.takesTurns)
        XCTAssertNil(chore.rotationRaw)
        XCTAssertEqual(chore.nextAssignee, kid)
    }

    func testRemovingTheKidWhoseTurnItIsPassesItOn() throws {
        let chore = try rotating([kid, ben, cleo])
        try service.removeMember(kid, by: parent)

        XCTAssertFalse(chore.isDeleted)
        XCTAssertEqual(chore.assignee, ben)
        XCTAssertEqual(chore.rotation, [ben, cleo])
    }

    func testRemovingAnotherKidJustShortensTheRotation() throws {
        let chore = try rotating([kid, ben, cleo])
        try service.removeMember(ben, by: parent)
        XCTAssertEqual(chore.assignee, kid)
        XCTAssertEqual(chore.nextAssignee, cleo)
    }

    func testDownToOneKidItStaysWithThem() throws {
        let chore = try rotating([kid, ben])
        try service.removeMember(ben, by: parent)
        XCTAssertFalse(chore.takesTurns)
        XCTAssertEqual(try finish(chore).assignee, kid)
    }

    func testRotationSurvivesStaleIDs() throws {
        let chore = try rotating([kid, ben])
        chore.rotationRaw = "not-a-uuid," + (chore.rotationRaw ?? "") + "," + UUID().uuidString
        XCTAssertEqual(chore.rotation, [kid, ben])
        XCTAssertEqual(chore.nextAssignee, ben)
    }
}
