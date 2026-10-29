import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

extension WidgetSnapshot {
    /// The widget's view of the household for `me`: their own chores if they're a kid,
    /// or every kid's progress and the review queue if they're a parent.
    init(household: Household, me: Member, now: Date = Date(), calendar: Calendar = .current) {
        let chores = (household.chores as? Set<Chore>) ?? []
        let kids = me.isParent ? household.kids : [me]
        self.init(
            householdName: household.displayName,
            isParent: me.isParent,
            kids: kids.map { Self.kid($0, chores: chores, now: now, calendar: calendar) },
            waitingForReview: me.isParent ? chores.filter { $0.status == .pendingReview }.count : 0)
    }

    private static func kid(_ member: Member, chores: Set<Chore>, now: Date, calendar: Calendar) -> Kid {
        let open = chores
            .filter { $0.assignee?.id == member.id && $0.status == .todo }
            .sorted { ($0.dueDate ?? .distantFuture, $0.displayTitle) < ($1.dueDate ?? .distantFuture, $1.displayTitle) }
            .prefix(20)
            .map { ChoreItem(title: $0.displayTitle, points: Int($0.points), due: $0.dueDate) }
        let goal = member.goal
        return Kid(name: member.displayName, emoji: member.displayEmoji, points: member.available,
                   streak: member.streak(now: now, calendar: calendar),
                   goalTitle: goal.map { "\($0.displayEmoji) \($0.displayTitle)" },
                   goalProgress: goal == nil ? nil : member.goalProgress,
                   open: Array(open))
    }

    /// Saves the snapshot and asks the widget to redraw if anything changed.
    static func publish(household: Household, me: Member) {
        #if os(iOS)
        let snapshot = WidgetSnapshot(household: household, me: me)
        if (try? snapshot.save()) == true {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        #endif
    }
}
