#if LOCAL_ONLY
import Foundation

extension HouseholdService {
    /// Testing aid for Local builds: a household with two parents, three kids and
    /// chores in every state, so each screen can be seen without setting up by hand.
    @discardableResult
    func loadDemoHousehold(userID: String) throws -> Household {
        let household = try createHousehold(name: "The Hendersons", yourName: "Mama", emoji: Theme.parentEmojis[0], userID: userID)
        guard let mama = household.memberList.first else { throw ServiceError.invalid("Demo household has no parent.") }

        try addMember(name: "Papa", role: .parent, emoji: Theme.parentEmojis[1], to: household, by: mama)
        let ava = try addMember(name: "Ava", role: .kid, emoji: Theme.kidEmojis[0], to: household, by: mama)
        let ben = try addMember(name: "Ben", role: .kid, emoji: Theme.kidEmojis[1], to: household, by: mama)
        try addMember(name: "Cleo", role: .kid, emoji: Theme.kidEmojis[2], to: household, by: mama)

        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

        var weekly = ChoreDraft(title: "Take out the trash", points: 5, dueDate: day(1))
        weekly.recurrence.kind = .weekly
        weekly.recurrence.weekdays = [calendar.component(.weekday, from: day(1))]
        try createChores(weekly, assignees: [ava, ben], in: household, by: mama)

        let waiting = try createChores(ChoreDraft(title: "Make your bed", points: 3, dueDate: today), assignees: [ava], in: household, by: mama)
        try markComplete(waiting[0], by: ava, note: "Done, with hospital corners!", photo: nil)

        let earned = try createChores(ChoreDraft(title: "Feed the cat", points: 4, dueDate: day(-1)), assignees: [ava], in: household, by: mama)
        try markComplete(earned[0], by: ava, note: nil, photo: nil)
        earned[0].completedAt = day(-1)
        try approve(earned[0], by: mama)

        // With today's bed and yesterday's cat, Ava is on a three-day streak.
        let older = try createChores(ChoreDraft(title: "Fold the laundry", points: 6, dueDate: day(-2)), assignees: [ava], in: household, by: mama)
        try markComplete(older[0], by: ava, note: nil, photo: nil)
        older[0].completedAt = day(-2)
        try approve(older[0], by: mama)

        let sentBack = try createChores(ChoreDraft(title: "Clean your room", notes: "Floor, desk and shelves.", points: 15, dueDate: today), assignees: [ben], in: household, by: mama)
        try markComplete(sentBack[0], by: ben, note: "All done", photo: nil)
        try reject(sentBack[0], by: mama, note: "There's still a sock under the bed.")

        try createChores(ChoreDraft(title: "Water the plants", points: 6, dueDate: day(-2)), assignees: [ben], in: household, by: mama)
        try createChores(ChoreDraft(title: "Set the table", notes: "Plates, forks and napkins.", points: 5), assignees: [household.kids[0]], in: household, by: mama)

        let movie = try saveReward(nil, title: "Movie night pick", emoji: "🎬", cost: 20, isActive: true, in: household, by: mama)
        try setGoal(movie, for: ava, by: mama)
        try saveReward(nil, title: "Ice cream trip", emoji: "🍦", cost: 4, isActive: true, in: household, by: mama)
        try saveReward(nil, title: "Extra screen time", emoji: "🎮", cost: 12, isActive: true, in: household, by: mama)
        return household
    }
}
#endif
