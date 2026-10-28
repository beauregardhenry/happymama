import Foundation
import UserNotifications

/// Local notifications driven by what the synced data says.
///
/// CloudKit delivers a silent push when another household member changes
/// something; Core Data imports it, and `AppEnvironment` calls `sync` afterwards.
/// We then turn anything new that concerns this person into a banner, and keep
/// due-date reminders scheduled for their open chores.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    func start() {
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    struct Event: Equatable {
        let key: String
        let title: String
        let body: String
    }

    func sync(household: Household, me: Member) {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            deliverNewEvents(household: household, me: me)
            await scheduleDueReminders(household: household, me: me)
        }
    }

    func events(household: Household, me: Member) -> [Event] {
        let chores = (household.chores as? Set<Chore>) ?? []
        let redemptions = (household.redemptions as? Set<Redemption>) ?? []
        var result: [Event] = []

        if me.isParent {
            for chore in chores where chore.status == .pendingReview {
                let when = chore.completedAt?.timeIntervalSince1970 ?? 0
                result.append(Event(
                    key: "review-\(chore.id?.uuidString ?? "")-\(when)",
                    title: "\(chore.assignee?.displayName ?? "Someone") finished a chore",
                    body: "\(chore.displayTitle) is ready for you to check."))
            }
            for request in redemptions where request.status == .requested {
                result.append(Event(
                    key: "redeem-\(request.id?.uuidString ?? "")",
                    title: "\(request.member?.displayName ?? "Someone") wants a reward",
                    body: "\(request.displayEmoji) \(request.displayTitle) · \(request.cost) pts"))
            }
        } else {
            for chore in chores where chore.assignee?.id == me.id {
                switch chore.status {
                case .todo where chore.wasSentBack:
                    let when = chore.reviewedAt?.timeIntervalSince1970 ?? 0
                    result.append(Event(
                        key: "sentback-\(chore.id?.uuidString ?? "")-\(when)",
                        title: "\(chore.displayTitle) needs another look",
                        body: chore.reviewNote ?? ""))
                case .todo:
                    result.append(Event(
                        key: "assigned-\(chore.id?.uuidString ?? "")",
                        title: "New chore: \(chore.displayTitle)",
                        body: "Worth \(chore.points) points."))
                case .approved:
                    guard let reviewed = chore.reviewedAt, reviewed > Date().addingTimeInterval(-86_400) else { continue }
                    result.append(Event(
                        key: "approved-\(chore.id?.uuidString ?? "")",
                        title: "You earned \(chore.awardedPoints) points!",
                        body: "\(chore.displayTitle) was approved."))
                case .pendingReview:
                    break
                }
            }
            for request in redemptions where request.member?.id == me.id && request.status != .requested {
                result.append(Event(
                    key: "decided-\(request.id?.uuidString ?? "")",
                    title: request.status == .approved ? "Reward approved!" : "Reward not approved",
                    body: "\(request.displayEmoji) \(request.displayTitle)"))
            }
        }
        return result
    }

    /// The first sync just records what already exists so installing doesn't flood the user.
    static func eventsToDeliver(current: [Event], seen: Set<String>, isFirstRun: Bool) -> [Event] {
        isFirstRun ? [] : current.filter { !seen.contains($0.key) }
    }

    private func deliverNewEvents(household: Household, me: Member) {
        let seenKey = "notified.\(me.id?.uuidString ?? "")"
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        let current = events(household: household, me: me)
        let isFirstRun = defaults.stringArray(forKey: seenKey) == nil

        for event in Notifier.eventsToDeliver(current: current, seen: seen, isFirstRun: isFirstRun) {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: event.key, content: content, trigger: nil))
        }
        seen.formUnion(current.map(\.key))
        defaults.set(Array(seen), forKey: seenKey)

        if me.isParent {
            let pending = current.count
            Task { try? await center.setBadgeCount(pending) }
        } else {
            Task { try? await center.setBadgeCount(0) }
        }
    }

    struct Reminder: Equatable {
        let id: String
        let title: String
        let body: String
        let fireAt: DateComponents
    }

    /// A 9am reminder on the due date for each of this kid's open chores, skipping
    /// any whose reminder time has already passed. Parents get none.
    static func dueReminders(household: Household, me: Member, now: Date = Date(),
                             calendar: Calendar = .current) -> [Reminder] {
        guard !me.isParent else { return [] }
        let chores = ((household.chores as? Set<Chore>) ?? []).filter {
            $0.assignee?.id == me.id && $0.status == .todo
        }
        return chores.compactMap { chore in
            guard let due = chore.dueDate, let id = chore.id else { return nil }
            var parts = calendar.dateComponents([.year, .month, .day], from: due)
            parts.hour = 9
            guard let fireDate = calendar.date(from: parts), fireDate > now else { return nil }
            return Reminder(id: "due-\(id.uuidString)", title: "Due today: \(chore.displayTitle)",
                            body: "Worth \(chore.points) points.", fireAt: parts)
        }
    }

    private func scheduleDueReminders(household: Household, me: Member) async {
        let existing = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("due-") }
        center.removePendingNotificationRequests(withIdentifiers: existing)
        for reminder in Notifier.dueReminders(household: household, me: me) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.fireAt, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}
