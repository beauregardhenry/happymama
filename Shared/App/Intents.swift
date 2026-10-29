import AppIntents
import Foundation

/// Who Siri is talking to: this device's household and the account owner's profile in it.
/// Tests point it at an in-memory household.
@MainActor
enum IntentContext {
    static var current: () async -> (household: Household, me: Member, service: HouseholdService)? = {
        await AppEnvironment.shared.intentContext()
    }

    static func require() async throws -> (household: Household, me: Member, service: HouseholdService) {
        guard let context = await current() else {
            throw ServiceError.invalid("Open Happy Mama first to set up your household.")
        }
        return context
    }
}

struct ChoreEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Chore"
    static var defaultQuery = ChoreQuery()

    let id: UUID
    let title: String
    let points: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(points) points")
    }

    @MainActor
    init(_ chore: Chore) {
        id = chore.id ?? UUID()
        title = chore.displayTitle
        points = Int(chore.points)
    }
}

/// Offers the speaker's own open chores, and finds one by name ("the dishes").
struct ChoreQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ChoreEntity] {
        try await Self.open().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ChoreEntity] {
        try await Self.open()
    }

    func entities(matching string: String) async throws -> [ChoreEntity] {
        try await Self.open(matching: string)
    }

    @MainActor
    private static func open(matching words: String = "") async throws -> [ChoreEntity] {
        let context = try await IntentContext.require()
        return AssistantReplies.openChores(for: context.me, matching: words).map(ChoreEntity.init)
    }
}

struct FinishChoreIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark a Chore Done"
    static var description = IntentDescription("Tells a parent you've finished one of your chores.")

    @Parameter(title: "Chore", requestValueDialog: "Which chore did you finish?")
    var chore: ChoreEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try await IntentContext.require()
        let reply = try AssistantReplies.finish(chore.id, household: context.household, me: context.me, service: context.service)
        return .result(dialog: "\(reply)")
    }
}

struct WhatsLeftIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Left Today"
    static var description = IntentDescription("For a parent, what's waiting for review. For a kid, what's left to do today.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try await IntentContext.require()
        return .result(dialog: "\(AssistantReplies.summary(household: context.household, me: context.me))")
    }
}

struct CheckPointsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Points"
    static var description = IntentDescription("Says how many points you have and how close you are to your goal.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try await IntentContext.require()
        return .result(dialog: "\(AssistantReplies.points(household: context.household, me: context.me))")
    }
}

struct HappyMamaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FinishChoreIntent(),
            phrases: [
                "I finished a chore in \(.applicationName)",
                "I finished \(\.$chore) in \(.applicationName)",
                "Mark \(\.$chore) done in \(.applicationName)",
            ],
            shortTitle: "Finish a Chore",
            systemImageName: "checkmark.circle")
        AppShortcut(
            intent: WhatsLeftIntent(),
            phrases: [
                "What's left in \(.applicationName)",
                "What's waiting in \(.applicationName)",
            ],
            shortTitle: "What's Left",
            systemImageName: "checklist")
        AppShortcut(
            intent: CheckPointsIntent(),
            phrases: [
                "How many points do I have in \(.applicationName)",
                "Check my \(.applicationName) points",
            ],
            shortTitle: "My Points",
            systemImageName: "star")
    }
}
