import Foundation

/// Ready-made chores grouped by age, so setting up a family takes seconds.
enum ChoreLibrary {
    enum Age: String, CaseIterable, Identifiable {
        case little, kids, tweens
        var id: String { rawValue }
        var title: String {
            switch self {
            case .little: "Little ones (3–5)"
            case .kids: "Kids (6–9)"
            case .tweens: "Tweens (10+)"
            }
        }
    }

    struct Template: Identifiable, Equatable {
        let title: String
        var notes = ""
        let points: Int
        let repeats: Recurrence
        let age: Age

        var id: String { "\(age.rawValue)-\(title)" }
    }

    static let templates: [Template] = [
        Template(title: "Make your bed", points: 2, repeats: .daily, age: .little),
        Template(title: "Put toys away", points: 2, repeats: .daily, age: .little),
        Template(title: "Clothes in the hamper", points: 1, repeats: .daily, age: .little),
        Template(title: "Feed the pet", notes: "With a grown-up's help.", points: 2, repeats: .daily, age: .little),
        Template(title: "Help set the table", points: 2, repeats: .daily, age: .little),
        Template(title: "Water the plants", points: 2, repeats: .weekly, age: .little),
        Template(title: "Match the socks", points: 2, repeats: .weekly, age: .little),

        Template(title: "Make your bed", points: 3, repeats: .daily, age: .kids),
        Template(title: "Pack your school bag", points: 2, repeats: .daily, age: .kids),
        Template(title: "Set the table", points: 3, repeats: .daily, age: .kids),
        Template(title: "Clear the table", points: 3, repeats: .daily, age: .kids),
        Template(title: "Empty the dishwasher", points: 5, repeats: .daily, age: .kids),
        Template(title: "Feed the pet", points: 3, repeats: .daily, age: .kids),
        Template(title: "Tidy your room", notes: "Floor, desk and bed.", points: 5, repeats: .weekly, age: .kids),
        Template(title: "Take out the trash", points: 4, repeats: .weekly, age: .kids),
        Template(title: "Fold the laundry", points: 5, repeats: .weekly, age: .kids),

        Template(title: "Load the dishwasher", points: 5, repeats: .daily, age: .tweens),
        Template(title: "Walk the dog", points: 5, repeats: .daily, age: .tweens),
        Template(title: "Trash and recycling out", points: 5, repeats: .weekly, age: .tweens),
        Template(title: "Vacuum the living room", points: 8, repeats: .weekly, age: .tweens),
        Template(title: "Clean the bathroom sink", notes: "Sink, tap and mirror.", points: 8, repeats: .weekly, age: .tweens),
        Template(title: "Do your own laundry", notes: "Wash, dry, fold and put away.", points: 10, repeats: .weekly, age: .tweens),
        Template(title: "Help cook dinner", points: 8, repeats: .weekly, age: .tweens),
        Template(title: "Mow the lawn", points: 15, repeats: .none, age: .tweens),
    ]

    static func templates(for age: Age) -> [Template] {
        templates.filter { $0.age == age }
    }

    /// A chore draft for the template. Repeating chores start today, since they need a date to repeat from.
    static func draft(from template: Template, today: Date = Date(), takeTurns: Bool = false) -> HouseholdService.ChoreDraft {
        var draft = HouseholdService.ChoreDraft()
        draft.title = template.title
        draft.notes = template.notes
        draft.points = template.points
        draft.recurrence.kind = template.repeats
        draft.dueDate = template.repeats == .none ? nil : today
        draft.takeTurns = takeTurns && template.repeats != .none
        return draft
    }
}

extension HouseholdService {
    /// Adds several library chores at once. Each kid gets a copy, or with `takeTurns`
    /// the kids take turns on the repeating ones.
    @discardableResult
    func addFromLibrary(_ templates: [ChoreLibrary.Template], assignees: [Member], takeTurns: Bool,
                        in household: Household, by me: Member) throws -> [Chore] {
        guard !templates.isEmpty else { throw ServiceError.invalid("Pick at least one chore.") }
        let turns = takeTurns && assignees.count > 1
        return try templates.flatMap { template in
            try createChores(ChoreLibrary.draft(from: template, takeTurns: turns), assignees: assignees, in: household, by: me)
        }
    }
}
