import XCTest
import UserNotifications
@testable import HappyMama

@MainActor
final class NotificationActionTests: ServiceTestCase {
    private func turnedIn(points: Int = 10) throws -> Chore {
        let chore = try assign(points: points)
        try service.markComplete(chore, by: kid, note: "done", photo: nil)
        return chore
    }

    private func requested(cost: Int = 5) throws -> Redemption {
        let earned = try turnedIn(points: 20)
        try service.approve(earned, by: parent)
        let reward = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: cost, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: reward, by: kid)
        return try XCTUnwrap((household.redemptions as? Set<Redemption>)?.first)
    }

    private func perform(_ action: Notifier.Action, on id: UUID?, note: String? = nil, by me: Member? = nil) throws {
        try Notifier.perform(action, on: try XCTUnwrap(id), note: note, household: household, me: me ?? parent, service: service)
    }

    func testReviewNotificationsCarryTheirButtons() throws {
        let chore = try turnedIn()
        let request = try requested()
        let events = Notifier().events(household: household, me: parent)

        let review = try XCTUnwrap(events.first { $0.objectID == chore.id })
        XCTAssertEqual(review.category, .choreReview)
        let reward = try XCTUnwrap(events.first { $0.objectID == request.id })
        XCTAssertEqual(reward.category, .rewardRequest)
        XCTAssertTrue(Notifier().events(household: household, me: kid).allSatisfy { $0.category == nil },
                      "kids' notifications have no buttons")
    }

    func testBannerCarriesTheCategoryAndWhatItIsAbout() throws {
        let chore = try turnedIn()
        let event = try XCTUnwrap(Notifier().events(household: household, me: parent).first)
        let content = event.content
        XCTAssertEqual(content.categoryIdentifier, Notifier.Category.choreReview.rawValue)
        XCTAssertEqual(content.title, "Sam finished a chore")

        let parsed = try XCTUnwrap(Notifier.parse(actionIdentifier: "approve-chore", userInfo: content.userInfo))
        XCTAssertEqual(parsed.0, .approveChore)
        XCTAssertEqual(parsed.1, chore.id)

        let plain = Notifier.Event(key: "k", title: "Hi", body: "There").content
        XCTAssertEqual(plain.categoryIdentifier, "")
        XCTAssertTrue(plain.userInfo.isEmpty)
    }

    func testPlainTapsAndBadPayloadsAreIgnored() {
        let info = [Notifier.objectIDKey: UUID().uuidString]
        XCTAssertNil(Notifier.parse(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: info))
        XCTAssertNil(Notifier.parse(actionIdentifier: "approve-chore", userInfo: [:]))
        XCTAssertNil(Notifier.parse(actionIdentifier: "approve-chore", userInfo: [Notifier.objectIDKey: "nope"]))
    }

    func testEveryButtonNeedsTheDeviceUnlocked() {
        let actions = Notifier.categories.flatMap(\.actions)
        XCTAssertEqual(Set(actions.map(\.identifier)), Set(Notifier.Action.allCases.map(\.rawValue)))
        XCTAssertTrue(actions.allSatisfy { $0.options.contains(.authenticationRequired) })
        XCTAssertTrue(actions.first { $0.identifier == Notifier.Action.sendBack.rawValue } is UNTextInputNotificationAction)
    }

    func testApproveFromNotificationAwardsPoints() throws {
        let chore = try turnedIn(points: 7)
        try perform(.approveChore, on: chore.id)
        XCTAssertEqual(chore.status, .approved)
        XCTAssertEqual(kid.balance, 7)
        XCTAssertEqual(chore.reviewedByName, "Mama")
    }

    func testSendBackFromNotificationKeepsTheTypedNote() throws {
        let chore = try turnedIn()
        try perform(.sendBack, on: chore.id, note: "Missed a spot")
        XCTAssertEqual(chore.status, .todo)
        XCTAssertEqual(chore.reviewNote, "Missed a spot")
        XCTAssertEqual(kid.balance, 0)

        let again = try turnedIn()
        try perform(.sendBack, on: again.id, note: nil)
        XCTAssertEqual(again.reviewNote, "Please take another look.")
    }

    func testRewardButtons() throws {
        let request = try requested(cost: 5)
        try perform(.approveReward, on: request.id)
        XCTAssertEqual(request.status, .approved)
        XCTAssertEqual(kid.balance, 15)

        let reward = try service.saveReward(nil, title: "Toy", emoji: "🧸", cost: 3, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: reward, by: kid)
        let second = try XCTUnwrap((household.redemptions as? Set<Redemption>)?.first { $0.status == .requested })
        try perform(.denyReward, on: second.id)
        XCTAssertEqual(second.status, .denied)
        XCTAssertEqual(kid.balance, 15)
    }

    func testAlreadyHandledOrMissingIsAnError() throws {
        let chore = try turnedIn()
        try perform(.approveChore, on: chore.id)
        assertThrowsServiceError(try perform(.approveChore, on: chore.id))
        XCTAssertEqual(kid.balance, 10, "the second tap awards nothing")

        assertThrowsServiceError(try perform(.approveChore, on: UUID()))
        assertThrowsServiceError(try perform(.denyReward, on: UUID()))
    }

    func testFailuresExplainThemselves() throws {
        // This message becomes the "Couldn't do that" banner.
        XCTAssertThrowsError(try perform(.approveChore, on: UUID())) { error in
            XCTAssertEqual(error.localizedDescription, "That chore is gone.")
        }
        XCTAssertEqual(ServiceError.notAllowed("Nope").localizedDescription, "Nope")
    }

    func testApprovingARewardTheKidCanNoLongerAffordFails() throws {
        let request = try requested(cost: 5)
        // The other parent's device removed the points this request was counting on.
        for entry in kid.entryList { service.context.delete(entry) }
        service.context.processPendingChanges()
        assertThrowsServiceError(try perform(.approveReward, on: request.id))
        XCTAssertEqual(request.status, .requested)
    }

    func testKidsCannotUseTheButtons() throws {
        let chore = try turnedIn()
        assertThrowsServiceError(try perform(.approveChore, on: chore.id, by: kid))
        XCTAssertEqual(chore.status, .pendingReview)
    }
}
