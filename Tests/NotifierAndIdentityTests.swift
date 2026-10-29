import XCTest
@testable import HappyMama

@MainActor
final class NotifierTests: ServiceTestCase {
    private let notifier = Notifier()

    private func titles(for member: Member) -> [String] {
        notifier.events(household: household, me: member).map(\.title)
    }

    func testParentIsToldAboutTurnedInChoresAndRewardRequests() throws {
        XCTAssertEqual(titles(for: parent), [])

        let chore = try assign(title: "Dishes")
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        let reward = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 1, isActive: true, in: household, by: parent)
        let other = try assign(title: "Bonus", points: 5)
        try service.markComplete(other, by: kid, note: nil, photo: nil)
        try service.approve(other, by: parent)
        try service.requestRedemption(of: reward, by: kid)

        let events = notifier.events(household: household, me: parent)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.contains { $0.title == "Sam finished a chore" && $0.body == "Dishes is ready for you to check. Worth 10 points." })
        XCTAssertTrue(events.contains { $0.title == "Sam wants a reward" && $0.body.contains("Treat") })
    }

    func testKidIsToldAboutNewChoresAndSentBackChores() throws {
        let chore = try assign(title: "Dishes", points: 8)
        XCTAssertEqual(notifier.events(household: household, me: kid).map(\.title), ["New chore: Dishes"])

        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        XCTAssertEqual(titles(for: kid), [], "waiting for review is not news to the kid")

        try service.reject(chore, by: parent, note: "Wipe the counter")
        let events = notifier.events(household: household, me: kid)
        XCTAssertEqual(events.map(\.title), ["Dishes needs another look"])
        XCTAssertEqual(events.first?.body, "Wipe the counter")
    }

    func testKidIsToldAboutApprovalsAndDecisions() throws {
        let chore = try assign(title: "Dishes", points: 8)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        XCTAssertEqual(titles(for: kid), ["You earned 8 points!"])

        let reward = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 3, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: reward, by: kid)
        let request = try XCTUnwrap((household.redemptions as? Set<Redemption>)?.first)
        XCTAssertFalse(titles(for: kid).contains("Reward approved!"), "undecided requests are silent")

        try service.decide(request, approve: false, by: parent)
        XCTAssertTrue(titles(for: kid).contains("Reward not approved"))
    }

    func testOldApprovalsAreNotRepeatedAsNews() throws {
        let chore = try assign(points: 8)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        chore.reviewedAt = Date().addingTimeInterval(-2 * 86_400)
        XCTAssertEqual(titles(for: kid), [])
    }

    func testKidIgnoresOtherKidsChores() throws {
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        _ = try assign(title: "Pip's chore", to: other)
        XCTAssertEqual(titles(for: kid), [])
        XCTAssertEqual(titles(for: other), ["New chore: Pip's chore"])
    }

    func testFirstSyncRecordsEventsWithoutNotifying() {
        let current = [Notifier.Event(key: "a", title: "A", body: ""), Notifier.Event(key: "b", title: "B", body: "")]
        XCTAssertEqual(Notifier.eventsToDeliver(current: current, seen: [], isFirstRun: true), [])
    }

    func testLaterSyncsOnlyDeliverUnseenEvents() {
        let a = Notifier.Event(key: "a", title: "A", body: "")
        let b = Notifier.Event(key: "b", title: "B", body: "")
        XCTAssertEqual(Notifier.eventsToDeliver(current: [a, b], seen: ["a"], isFirstRun: false), [b])
        XCTAssertEqual(Notifier.eventsToDeliver(current: [a, b], seen: ["a", "b"], isFirstRun: false), [])
    }

    func testSentBackAgainCountsAsNewEvent() throws {
        let chore = try assign()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.reject(chore, by: parent, note: "First")
        let first = notifier.events(household: household, me: kid).map(\.key)

        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        chore.reviewedAt = nil
        try service.reject(chore, by: parent, note: "Second")
        chore.reviewedAt = Date().addingTimeInterval(60)
        let second = notifier.events(household: household, me: kid).map(\.key)

        XCTAssertNotEqual(first, second, "each send-back gets its own key so it notifies again")
    }
}

#if LOCAL_ONLY
@MainActor
final class IdentityTests: XCTestCase {
    private let key = "localUserID"
    private var saved: String?

    override func setUp() {
        saved = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }

    func testLocalIdentityIsCreatedOnceAndReused() async {
        let identity = Identity()
        await identity.refresh()
        let first = identity.userID
        XCTAssertTrue(first?.hasPrefix("local-") ?? false)
        XCTAssertEqual(identity.status, .available)

        let again = Identity()
        await again.refresh()
        XCTAssertEqual(again.userID, first)
    }

    func testActAsSwitchesToAClaimedMember() async throws {
        let service = HouseholdService(persistence: PersistenceController(mode: .inMemory), autoClaimNewMembers: true)
        let household = try service.createHousehold(name: "T", yourName: "Mama", emoji: "🌻", userID: "u-mama")
        let kid = try service.addMember(name: "Sam", role: .kid, emoji: "🦊", to: household, by: try XCTUnwrap(household.parents.first))

        let identity = Identity()
        await identity.refresh()
        identity.actAs(kid)
        XCTAssertEqual(identity.userID, kid.appleUserID)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), kid.appleUserID)

        let unclaimed = Member(context: service.context)
        identity.actAs(unclaimed)
        XCTAssertEqual(identity.userID, kid.appleUserID, "an unclaimed profile can't be acted as")
        service.context.rollback()
    }
}
#endif
