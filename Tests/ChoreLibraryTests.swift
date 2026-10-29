import XCTest
@testable import HappyMama

@MainActor
final class ChoreLibraryTests: ServiceTestCase {
    private func template(_ title: String, _ age: ChoreLibrary.Age = .kids) throws -> ChoreLibrary.Template {
        try XCTUnwrap(ChoreLibrary.templates.first { $0.title == title && $0.age == age })
    }

    func testEveryAgeHasIdeasAndIDsAreUnique() {
        for age in ChoreLibrary.Age.allCases {
            XCTAssertGreaterThanOrEqual(ChoreLibrary.templates(for: age).count, 5, age.title)
        }
        let ids = ChoreLibrary.templates.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ChoreLibrary.templates.allSatisfy { $0.points > 0 })
    }

    func testRepeatingIdeasStartTodayAndOneOffsHaveNoDate() throws {
        let today = Date()
        let daily = ChoreLibrary.draft(from: try template("Set the table"), today: today)
        XCTAssertEqual(daily.title, "Set the table")
        XCTAssertEqual(daily.points, 3)
        XCTAssertEqual(daily.recurrence.kind, .daily)
        XCTAssertEqual(daily.dueDate, today)

        let once = ChoreLibrary.draft(from: try template("Mow the lawn", .tweens), today: today, takeTurns: true)
        XCTAssertNil(once.dueDate)
        XCTAssertFalse(once.takeTurns, "one-off chores can't rotate")
    }

    func testAddingSeveralGivesEachKidACopy() throws {
        let ben = try service.addMember(name: "Ben", role: .kid, emoji: "🐼", to: household, by: parent)
        let picks = [try template("Set the table"), try template("Tidy your room")]
        let created = try service.addFromLibrary(picks, assignees: [kid, ben], takeTurns: false, in: household, by: parent)

        XCTAssertEqual(created.count, 4)
        XCTAssertEqual(Set(created.compactMap(\.assignee)), [kid, ben])
        let tidy = try XCTUnwrap(created.first { $0.displayTitle == "Tidy your room" })
        XCTAssertEqual(tidy.notes, "Floor, desk and bed.")
        XCTAssertEqual(tidy.recurrence.kind, .weekly)
    }

    func testTakingTurnsAppliesOnlyToRepeatingIdeas() throws {
        let ben = try service.addMember(name: "Ben", role: .kid, emoji: "🐼", to: household, by: parent)
        let picks = [try template("Take out the trash"), try template("Mow the lawn", .tweens)]
        let created = try service.addFromLibrary(picks, assignees: [kid, ben], takeTurns: true, in: household, by: parent)

        XCTAssertEqual(created.filter { $0.displayTitle == "Take out the trash" }.count, 1)
        XCTAssertTrue(try XCTUnwrap(created.first { $0.displayTitle == "Take out the trash" }).takesTurns)
        XCTAssertEqual(created.filter { $0.displayTitle == "Mow the lawn" }.count, 2)
    }

    func testTakingTurnsWithOneKidJustAssignsIt() throws {
        let created = try service.addFromLibrary([try template("Set the table")], assignees: [kid], takeTurns: true,
                                                 in: household, by: parent)
        XCTAssertEqual(created.count, 1)
        XCTAssertFalse(created[0].takesTurns)
    }

    func testLibraryRules() throws {
        assertThrowsServiceError(try service.addFromLibrary([], assignees: [kid], takeTurns: false, in: household, by: parent))
        assertThrowsServiceError(try service.addFromLibrary([try template("Set the table")], assignees: [kid], takeTurns: false,
                                                            in: household, by: kid))
        assertThrowsServiceError(try service.addFromLibrary([try template("Set the table")], assignees: [], takeTurns: false,
                                                            in: household, by: parent))
    }
}
