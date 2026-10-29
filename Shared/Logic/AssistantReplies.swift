import Foundation

/// What Siri and Shortcuts say and do. Kept apart from the App Intents types so the
/// wording and the rules can be tested without the system running an intent.
@MainActor
enum AssistantReplies {
    /// The chores this person could say they've finished: their own open ones, soonest due first.
    static func openChores(for me: Member) -> [Chore] {
        guard !me.isParent else { return [] }
        return ((me.assignedChores as? Set<Chore>) ?? [])
            .filter { $0.status == .todo }
            .sorted { ($0.dueAt() ?? .distantFuture, $0.displayTitle) < ($1.dueAt() ?? .distantFuture, $1.displayTitle) }
    }

    /// Open chores whose title contains the spoken words, ignoring case and accents.
    static func openChores(for me: Member, matching words: String) -> [Chore] {
        let words = words.trimmed
        guard !words.isEmpty else { return openChores(for: me) }
        return openChores(for: me).filter {
            $0.displayTitle.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Marks the chore done and says what happens next.
    static func finish(_ choreID: UUID, household: Household, me: Member, service: HouseholdService) throws -> String {
        guard let chore = ((household.chores as? Set<Chore>) ?? []).first(where: { $0.id == choreID }) else {
            throw ServiceError.invalid("I couldn't find that chore.")
        }
        try service.markComplete(chore, by: me, note: nil, photo: nil)
        if chore.status == .approved {
            return "Nice work! You earned \(chore.awardedPoints) \(pointsWord(Int(chore.awardedPoints))) for \(chore.displayTitle)."
        }
        return "Nice work! \(chore.displayTitle) is waiting for a parent to check."
    }

    /// For a parent: what's waiting for them. For a kid: what they still have to do today.
    static func summary(household: Household, me: Member, now: Date = Date(), calendar: Calendar = .current) -> String {
        if me.isParent {
            let chores = ((household.chores as? Set<Chore>) ?? []).filter { $0.status == .pendingReview }.count
            let requests = ((household.redemptions as? Set<Redemption>) ?? []).filter { $0.status == .requested }.count
            let parts = [phrase(chores, "chore"), phrase(requests, "reward request")].compactMap { $0 }
            guard !parts.isEmpty else { return "You're all caught up. Nothing is waiting for review." }
            let verb = chores + requests == 1 ? "is" : "are"
            let sentence = parts.joined(separator: " and ") + " \(verb) waiting for you."
            return sentence.prefix(1).uppercased() + sentence.dropFirst()
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return "" }
        let today = openChores(for: me).filter { ($0.dueDate ?? .distantPast) < tomorrow }
        switch today.count {
        case 0: return "You're all done for today!"
        case 1: return "You have one chore left today: \(today[0].displayTitle)."
        default:
            let names = today.prefix(3).map(\.displayTitle)
            let more = today.count > 3 ? ", and \(today.count - 3) more" : ""
            return "You have \(today.count) chores left today: \(names.joined(separator: ", "))\(more)."
        }
    }

    /// A kid's points and goal, or every kid's points for a parent.
    static func points(household: Household, me: Member) -> String {
        if me.isParent {
            let kids = household.kids
            guard !kids.isEmpty else { return "There are no kids in your household yet." }
            return kids.map { "\($0.displayName) has \($0.available)" }.joined(separator: ", ") + "."
        }
        var reply = "You have \(me.available) \(pointsWord(me.available))."
        if me.reserved > 0 { reply += " \(me.reserved) more are on hold for a reward request." }
        if let goal = me.goal {
            let left = Int(goal.cost) - me.available
            reply += left > 0
                ? " \(left) more for \(goal.displayTitle)."
                : " That's enough for \(goal.displayTitle)!"
        }
        return reply
    }

    private static func pointsWord(_ n: Int) -> String { n == 1 ? "point" : "points" }

    /// "one chore", "3 chores", or nil for none.
    private static func phrase(_ n: Int, _ noun: String) -> String? {
        switch n {
        case 0: nil
        case 1: "one \(noun)"
        default: "\(n) \(noun)s"
        }
    }
}
