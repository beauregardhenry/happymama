import WidgetKit
import SwiftUI

@main
struct HappyMamaWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), snapshot: context.isPreview ? .preview : WidgetSnapshot.load() ?? .preview))
    }

    /// The app reloads the widget whenever something changes; otherwise it only needs
    /// to redraw at midnight, when "today" moves on.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        let entries = [TodayEntry(date: now, snapshot: WidgetSnapshot.load()),
                       TodayEntry(date: midnight, snapshot: WidgetSnapshot.load())]
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.happy.opacity(0.08) }
        }
        .configurationDisplayName("Today")
        .description("Today's chores and points, or what's waiting for a parent to review.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        householdName: "The Hendersons", isParent: false,
        kids: [Kid(name: "Ava", emoji: "🦊", points: 24, streak: 3, goalTitle: "🎬 Movie night", goalProgress: 0.6,
                   open: [ChoreItem(title: "Make your bed", points: 3, due: Date()),
                          ChoreItem(title: "Feed the cat", points: 4, due: Date()),
                          ChoreItem(title: "Set the table", points: 5, due: nil)])],
        waitingForReview: 0)
}

extension Color {
    /// The app's coral (Theme.accent), which the widget can't import from the app.
    static let happy = Color(red: 0.91, green: 0.35, blue: 0.32)
}
