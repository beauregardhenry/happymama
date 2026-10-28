import XCTest
@testable import HappyMama

@MainActor
final class MemberManagementTests: ServiceTestCase {
    private func addSecondParent() throws -> Member {
        try service.addMember(name: "Papa", role: .parent, emoji: "🌷", to: household, by: parent)
    }

    func testUpdateMemberChangesNameRoleAndEmoji() throws {
        let papa = try addSecondParent()
        try service.updateMember(kid, name: "  Samuel ", role: .kid, emoji: "🐼", by: parent)
        XCTAssertEqual(kid.name, "Samuel")
        XCTAssertEqual(kid.emoji, "🐼")

        try service.updateMember(kid, name: "Samuel", role: .parent, emoji: "🐼", by: papa)
        XCTAssertTrue(kid.isParent)
    }

    func testUpdateMemberRejectsBlankNameAndKids() {
        assertThrowsServiceError(try service.updateMember(kid, name: "  ", role: .kid, emoji: "🦊", by: parent))
        assertThrowsServiceError(try service.updateMember(kid, name: "Sam", role: .kid, emoji: "🦊", by: kid))
    }

    func testCannotDemoteLastParentOrYourself() throws {
        assertThrowsServiceError(try service.updateMember(parent, name: "Mama", role: .kid, emoji: "🌻", by: parent))

        _ = try addSecondParent()
        assertThrowsServiceError(try service.updateMember(parent, name: "Mama", role: .kid, emoji: "🌻", by: parent))
        XCTAssertTrue(parent.isParent)
    }

    func testRemoveMemberDeletesKidAndExtraParent() throws {
        let papa = try addSecondParent()
        try service.removeMember(kid, by: parent)
        XCTAssertEqual(household.kids.count, 0)

        try service.removeMember(papa, by: parent)
        XCTAssertEqual(household.parents.count, 1)
    }

    func testKidCannotRemoveMembers() throws {
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        assertThrowsServiceError(try service.removeMember(other, by: kid))
        XCTAssertEqual(household.kids.count, 2)
    }

    func testResetSignInFreesTheProfileButNotYourOwn() throws {
        try service.claim(kid, userID: "u-kid", parentCode: nil)
        XCTAssertTrue(kid.isClaimed)

        try service.resetSignIn(of: kid, by: parent)
        XCTAssertFalse(kid.isClaimed)
        assertThrowsServiceError(try service.resetSignIn(of: parent, by: parent))
        assertThrowsServiceError(try service.resetSignIn(of: parent, by: kid))
    }

    func testCannotClaimAProfileSomeoneAlreadyHas() throws {
        try service.claim(kid, userID: "u-kid", parentCode: nil)
        assertThrowsServiceError(try service.claim(kid, userID: "u-other", parentCode: nil))
        XCTAssertEqual(kid.appleUserID, "u-kid")
    }

    func testJoinAsKidCreatesAClaimedKid() throws {
        let joined = try service.joinAsKid(name: " Robin ", emoji: "🐧", userID: "u-robin", household: household)
        XCTAssertEqual(joined.name, "Robin")
        XCTAssertFalse(joined.isParent)
        XCTAssertEqual(joined.appleUserID, "u-robin")
        XCTAssertEqual(household.kids.count, 2)

        assertThrowsServiceError(try service.joinAsKid(name: " ", emoji: "🐧", userID: "u-x", household: household))
    }

    func testAutoClaimGivesNewMembersAStandInSignIn() throws {
        service.autoClaimNewMembers = true
        let added = try service.addMember(name: "Test", role: .kid, emoji: "🦊", to: household, by: parent)
        XCTAssertTrue(added.isClaimed)
        XCTAssertTrue(added.appleUserID?.hasPrefix("local-") ?? false)
    }
}
