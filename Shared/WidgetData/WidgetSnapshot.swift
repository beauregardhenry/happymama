import Foundation

/// What the home-screen widget shows, written by the app into the shared app group
/// container. The widget can't open the Core Data store, so it reads this instead.
/// Compiled into both the app and the widget extension, so it uses Foundation only.
struct WidgetSnapshot: Codable, Equatable {
    struct ChoreItem: Codable, Equatable {
        var title: String
        var points: Int
        var due: Date?
        /// Minutes after midnight, when the chore is due by a time.
        var dueTime: Int?
    }

    struct Kid: Codable, Equatable {
        var name: String
        var emoji: String
        var points: Int
        var streak: Int
        var goalTitle: String?
        var goalProgress: Double?
        /// Open chores, soonest due first, undated last.
        var open: [ChoreItem]

        /// What's left for the day of `now`: anything due by then, plus undated chores.
        func today(now: Date = Date(), calendar: Calendar = .current) -> [ChoreItem] {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return open }
            return open.filter { ($0.due ?? .distantPast) < tomorrow }
        }
    }

    var householdName: String
    var isParent: Bool
    /// For a kid, just them; for a parent, every kid in the household.
    var kids: [Kid]
    var waitingForReview: Int

    static let appGroup = "group.com.happymama.HappyMama"
    static let kind = "Today"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func load(from url: URL? = fileURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Writes the snapshot, returning false when nothing changed so the widget needn't reload.
    @discardableResult
    func save(to url: URL? = Self.fileURL) throws -> Bool {
        guard let url else { return false }
        if Self.load(from: url) == self { return false }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        return true
    }
}
