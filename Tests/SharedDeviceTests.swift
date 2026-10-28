import XCTest
@testable import HappyMama

@MainActor
final class SharedDeviceTests: ServiceTestCase {
    private var defaults: UserDefaults!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var device: SharedDevice!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "SharedDeviceTests")
        defaults.removePersistentDomain(forName: "SharedDeviceTests")
        device = makeDevice()
        household.parentCode = "2468"
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "SharedDeviceTests")
        try await super.tearDown()
    }

    private func makeDevice() -> SharedDevice {
        SharedDevice(defaults: defaults) { [unowned self] in self.clock }
    }

    func testOffByDefaultAndNobodyIsActive() {
        XCTAssertFalse(device.isEnabled)
        XCTAssertNil(device.activeMember(in: household))
    }

    func testEnablingKeepsTheParentSignedInAndIsRemembered() {
        device.enable(as: parent)
        XCTAssertEqual(device.activeMember(in: household)?.id, parent.id)
        XCTAssertTrue(makeDevice().isEnabled, "the setting survives a relaunch")
        XCTAssertNil(makeDevice().activeMember(in: household), "but the session does not")
    }

    func testKidsCannotTurnItOn() {
        device.enable(as: kid)
        XCTAssertFalse(device.isEnabled)
    }

    func testKidsGoStraightIn() throws {
        device.enable(as: parent)
        device.signOut()
        try device.signIn(kid)
        XCTAssertEqual(device.activeMember(in: household)?.id, kid.id)
    }

    func testParentsNeedTheCode() throws {
        device.enable(as: parent)
        device.signOut()
        assertThrowsServiceError(try device.signIn(parent))
        assertThrowsServiceError(try device.signIn(parent, code: "1111"))
        XCTAssertNil(device.activeMember(in: household))

        try device.signIn(parent, code: " 2468 ")
        XCTAssertEqual(device.activeMember(in: household)?.id, parent.id)
    }

    func testTooManyWrongCodesLocksParentsOutForAMinute() throws {
        device.enable(as: parent)
        for _ in 0..<SharedDevice.maxAttempts {
            assertThrowsServiceError(try device.signIn(parent, code: "0000"))
        }
        // Even the right code waits out the lockout.
        assertThrowsServiceError(try device.signIn(parent, code: "2468"))
        try device.signIn(kid)

        clock.addTimeInterval(SharedDevice.lockout + 1)
        try device.signIn(parent, code: "2468")
        XCTAssertEqual(device.activeMember(in: household)?.id, parent.id)
    }

    func testARightCodeResetsTheWrongCount() throws {
        device.enable(as: parent)
        for _ in 0..<(SharedDevice.maxAttempts - 1) {
            assertThrowsServiceError(try device.signIn(parent, code: "0000"))
        }
        try device.signIn(parent, code: "2468")
        assertThrowsServiceError(try device.signIn(parent, code: "0000"))
        try device.signIn(parent, code: "2468")
    }

    func testTurningOffEndsTheSession() {
        device.enable(as: parent)
        device.isEnabled = false
        XCTAssertNil(device.activeMember(in: household))
        XCTAssertFalse(makeDevice().isEnabled)
    }

    func testRemovedMemberIsNoLongerActive() throws {
        device.enable(as: parent)
        try device.signIn(kid)
        try service.removeMember(kid, by: parent)
        XCTAssertNil(device.activeMember(in: household))
    }

    // MARK: Parent code

    func testParentsCanSetAMemorableCode() throws {
        try service.setParentCode(" 1357 ", for: household, by: parent)
        XCTAssertEqual(household.parentCode, "1357")
    }

    func testParentCodeRules() {
        assertThrowsServiceError(try service.setParentCode("123", for: household, by: parent))
        assertThrowsServiceError(try service.setParentCode("123456789", for: household, by: parent))
        assertThrowsServiceError(try service.setParentCode("12a4", for: household, by: parent))
        assertThrowsServiceError(try service.setParentCode("١٢٣٤", for: household, by: parent))
        assertThrowsServiceError(try service.setParentCode("1234", for: household, by: kid))
        XCTAssertEqual(household.parentCode, "2468")
    }
}
