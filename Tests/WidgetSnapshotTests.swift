import XCTest
@testable import HappyMama

@MainActor
final class WidgetSnapshotTests: ServiceTestCase {
    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

    private func snapshot(for member: Member) -> WidgetSnapshot {
        WidgetSnapshot(household: household, me: member, now: Date(), calendar: calendar)
    }

    func testKidSeesTheirOwnOpenChoresSoonestFirst() throws {
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        _ = try assign(title: "Later", due: day(3))
        _ = try assign(title: "Whenever")
        _ = try assign(title: "Late", due: day(-1))
        _ = try assign(title: "Pip's", to: other, due: day(0))
        let done = try assign(title: "Turned in", due: day(0))
        try service.markComplete(done, by: kid, note: nil, photo: nil)

        let snap = snapshot(for: kid)
        XCTAssertFalse(snap.isParent)
        XCTAssertEqual(snap.kids.map(\.name), ["Sam"])
        XCTAssertEqual(snap.kids[0].open.map(\.title), ["Late", "Later", "Whenever"])
        XCTAssertEqual(snap.kids[0].emoji, "🦊")
        XCTAssertEqual(snap.waitingForReview, 0)
    }

    func testTodayIsDueByTodayPlusUndated() throws {
        _ = try assign(title: "Later", due: day(3))
        _ = try assign(title: "Whenever")
        _ = try assign(title: "Today", due: day(0))
        let kidSnap = try XCTUnwrap(snapshot(for: kid).kids.first)

        XCTAssertEqual(kidSnap.today(now: Date(), calendar: calendar).map(\.title), ["Today", "Whenever"])
        // Three days on, the later one is due too, without the app writing a new snapshot.
        XCTAssertEqual(kidSnap.today(now: day(3), calendar: calendar).count, 3)
    }

    func testParentSeesEveryKidAndTheReviewQueue() throws {
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        let chore = try assign(points: 6)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        _ = try assign(title: "Pip's", to: other)

        let snap = snapshot(for: parent)
        XCTAssertTrue(snap.isParent)
        XCTAssertEqual(snap.householdName, "Test")
        XCTAssertEqual(snap.kids.map(\.name), ["Pip", "Sam"])
        XCTAssertEqual(snap.waitingForReview, 1)
        XCTAssertEqual(snap.kids.first { $0.name == "Pip" }?.open.count, 1)
    }

    func testPointsStreakAndGoal() throws {
        let chore = try assign(points: 10)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let movie = try service.saveReward(nil, title: "Movie", emoji: "🎬", cost: 20, isActive: true, in: household, by: parent)

        var kidSnap = try XCTUnwrap(snapshot(for: kid).kids.first)
        XCTAssertEqual(kidSnap.points, 10)
        XCTAssertEqual(kidSnap.streak, 1)
        XCTAssertNil(kidSnap.goalTitle)
        XCTAssertNil(kidSnap.goalProgress)

        try service.setGoal(movie, for: kid, by: kid)
        kidSnap = try XCTUnwrap(snapshot(for: kid).kids.first)
        XCTAssertEqual(kidSnap.goalTitle, "🎬 Movie")
        XCTAssertEqual(try XCTUnwrap(kidSnap.goalProgress), 0.5, accuracy: 0.001)
    }

    func testSaveRoundTripsAndSkipsUnchangedWrites() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try assign(title: "Dishes", due: day(0))
        let snap = snapshot(for: kid)

        XCTAssertNil(WidgetSnapshot.load(from: url))
        XCTAssertTrue(try snap.save(to: url))
        XCTAssertEqual(WidgetSnapshot.load(from: url), snap)
        XCTAssertFalse(try snap.save(to: url), "nothing changed, so the widget needn't reload")

        _ = try assign(title: "Trash")
        XCTAssertTrue(try snapshot(for: kid).save(to: url))
        XCTAssertFalse(try snap.save(to: nil), "no app group container, nothing written")
    }
}
