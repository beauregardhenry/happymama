import XCTest
import CoreData
@testable import HappyMama

/// A household with one parent (Mama) and one kid (Sam) on an in-memory store.
@MainActor
class ServiceTestCase: XCTestCase {
    var service: HouseholdService!
    var household: Household!
    var parent: Member!
    var kid: Member!
    var calendar: Calendar!

    override func setUp() async throws {
        service = HouseholdService(persistence: PersistenceController(mode: .inMemory))
        calendar = Calendar(identifier: .gregorian)
        service.calendar = calendar
        household = try service.createHousehold(name: "Test", yourName: "Mama", emoji: "🌻", userID: "u-parent")
        parent = household.parents.first
        kid = try service.addMember(name: "Sam", role: .kid, emoji: "🦊", to: household, by: parent)
    }

    func assign(title: String = "Dishes", points: Int = 10, to member: Member? = nil, due: Date? = nil,
                recurrence: RecurrenceRule = .init()) throws -> Chore {
        var draft = HouseholdService.ChoreDraft()
        draft.title = title
        draft.points = points
        draft.dueDate = due
        draft.recurrence = recurrence
        return try service.createChores(draft, assignees: [member ?? kid], in: household, by: parent)[0]
    }

    func assertThrowsServiceError<T>(_ work: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try work(), file: file, line: line) { error in
            XCTAssertTrue(error is ServiceError, "expected ServiceError, got \(error)", file: file, line: line)
        }
    }
}
