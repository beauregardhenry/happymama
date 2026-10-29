import XCTest
@testable import HappyMama

@MainActor
final class AssistantRepliesTests: ServiceTestCase {
    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

    func testOpenChoresAreTheKidsOwnSoonestFirst() throws {
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        _ = try assign(title: "Later", due: day(2))
        _ = try assign(title: "Now", due: day(0))
        _ = try assign(title: "Pip's", to: other)
        let done = try assign(title: "Done")
        try service.markComplete(done, by: kid, note: nil, photo: nil)

        XCTAssertEqual(AssistantReplies.openChores(for: kid).map(\.displayTitle), ["Now", "Later"])
        XCTAssertEqual(AssistantReplies.openChores(for: parent), [])
    }

    func testFindsAChoreByWhatWasSaid() throws {
        _ = try assign(title: "Empty the dishwasher")
        _ = try assign(title: "Feed the cat")
        XCTAssertEqual(AssistantReplies.openChores(for: kid, matching: "DISHWASHER").map(\.displayTitle), ["Empty the dishwasher"])
        XCTAssertEqual(AssistantReplies.openChores(for: kid, matching: "  ").count, 2)
        XCTAssertTrue(AssistantReplies.openChores(for: kid, matching: "lawn").isEmpty)
    }

    func testFinishingTellsTheKidWhatHappensNext() throws {
        let chore = try assign(title: "Dishes")
        let reply = try AssistantReplies.finish(try XCTUnwrap(chore.id), household: household, me: kid, service: service)
        XCTAssertEqual(reply, "Nice work! Dishes is waiting for a parent to check.")
        XCTAssertEqual(chore.status, .pendingReview)
    }

    func testFinishingAnAutomaticChoreAwardsThePoints() throws {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Teeth"
        draft.points = 1
        draft.autoApprove = true
        let chore = try service.createChores(draft, assignees: [kid], in: household, by: parent)[0]
        let reply = try AssistantReplies.finish(try XCTUnwrap(chore.id), household: household, me: kid, service: service)
        XCTAssertEqual(reply, "Nice work! You earned 1 point for Teeth.")
    }

    func testFinishingFollowsTheUsualRules() throws {
        let chore = try assign()
        let id = try XCTUnwrap(chore.id)
        assertThrowsServiceError(try AssistantReplies.finish(id, household: household, me: parent, service: service))
        assertThrowsServiceError(try AssistantReplies.finish(UUID(), household: household, me: kid, service: service))
        _ = try AssistantReplies.finish(id, household: household, me: kid, service: service)
        assertThrowsServiceError(try AssistantReplies.finish(id, household: household, me: kid, service: service))
    }

    func testParentSummary() throws {
        XCTAssertEqual(AssistantReplies.summary(household: household, me: parent),
                       "You're all caught up. Nothing is waiting for review.")
        let chore = try assign(points: 20)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        XCTAssertEqual(AssistantReplies.summary(household: household, me: parent), "One chore is waiting for you.")

        try service.approve(chore, by: parent)
        let reward = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 2, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: reward, by: kid)
        XCTAssertEqual(AssistantReplies.summary(household: household, me: parent), "One reward request is waiting for you.")

        for title in ["A", "B"] {
            let more = try assign(title: title)
            try service.markComplete(more, by: kid, note: nil, photo: nil)
        }
        XCTAssertEqual(AssistantReplies.summary(household: household, me: parent),
                       "2 chores and one reward request are waiting for you.")
    }

    func testKidSummaryCountsWhatsLeftToday() throws {
        let now = day(0).addingTimeInterval(12 * 3600)
        func summary() -> String { AssistantReplies.summary(household: household, me: kid, now: now, calendar: calendar) }
        XCTAssertEqual(summary(), "You're all done for today!")

        _ = try assign(title: "Later", due: day(3))
        _ = try assign(title: "Dishes", due: day(0))
        XCTAssertEqual(summary(), "You have one chore left today: Dishes.")

        for title in ["Bed", "Cat", "Plants"] { _ = try assign(title: title) }
        XCTAssertEqual(summary(), "You have 4 chores left today: Dishes, Bed, Cat, and 1 more.")
    }

    func testPoints() throws {
        XCTAssertEqual(AssistantReplies.points(household: household, me: kid), "You have 0 points.")
        let chore = try assign(points: 10)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let movie = try service.saveReward(nil, title: "Movie", emoji: "🎬", cost: 15, isActive: true, in: household, by: parent)
        try service.setGoal(movie, for: kid, by: kid)
        XCTAssertEqual(AssistantReplies.points(household: household, me: kid), "You have 10 points. 5 more for Movie.")

        let treat = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 1, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: treat, by: kid)
        XCTAssertEqual(AssistantReplies.points(household: household, me: kid),
                       "You have 9 points. 1 more are on hold for a reward request. 6 more for Movie.")

        try service.setGoal(treat, for: kid, by: kid)
        XCTAssertTrue(AssistantReplies.points(household: household, me: kid).hasSuffix("That's enough for Treat!"))
        XCTAssertEqual(AssistantReplies.points(household: household, me: parent), "Sam has 9.")
    }

    func testParentPointsWithNoKids() throws {
        try service.removeMember(kid, by: parent)
        XCTAssertEqual(AssistantReplies.points(household: household, me: parent), "There are no kids in your household yet.")
    }
}

@MainActor
final class IntentTests: ServiceTestCase {
    private var saved: (() async -> (household: Household, me: Member, service: HouseholdService)?)!

    override func setUp() async throws {
        try await super.setUp()
        saved = IntentContext.current
    }

    override func tearDown() async throws {
        IntentContext.current = saved
        try await super.tearDown()
    }

    private func speak(as member: Member) {
        let household = household!, service = service!
        IntentContext.current = { (household, member, service) }
    }

    func testKidFindsAndFinishesAChore() async throws {
        let chore = try assign(title: "Dishes", points: 4)
        speak(as: kid)
        let query = ChoreQuery()
        let suggested = try await query.suggestedEntities()
        XCTAssertEqual(suggested.map(\.title), ["Dishes"])
        XCTAssertEqual(suggested.first?.points, 4)
        let id = try XCTUnwrap(chore.id)
        let matched = try await query.entities(matching: "dish")
        XCTAssertEqual(matched.map(\.id), [id])
        let byID = try await query.entities(for: [id])
        XCTAssertEqual(byID.count, 1)

        var intent = FinishChoreIntent()
        intent.chore = try XCTUnwrap(suggested.first)
        _ = try await intent.perform()
        XCTAssertEqual(chore.status, .pendingReview)
    }

    func testSummaryAndPointsIntentsRun() async throws {
        speak(as: parent)
        _ = try await WhatsLeftIntent().perform()
        _ = try await CheckPointsIntent().perform()
        let suggested = try await ChoreQuery().suggestedEntities()
        XCTAssertTrue(suggested.isEmpty, "parents have no chores to finish")
    }

    func testShortcutsAndChoreDisplay() throws {
        XCTAssertEqual(HappyMamaShortcuts.appShortcuts.count, 3)
        let entity = ChoreEntity(try assign(title: "Dishes", points: 4))
        XCTAssertEqual(String(localized: entity.displayRepresentation.title), "Dishes")
        XCTAssertNotNil(entity.displayRepresentation.subtitle)
        XCTAssertEqual(String(localized: FinishChoreIntent.title), "Mark a Chore Done")
    }

    func testWithoutAHouseholdIntentsExplain() async throws {
        IntentContext.current = { nil }
        do {
            _ = try await CheckPointsIntent().perform()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Open Happy Mama first to set up your household.")
        }
    }
}
