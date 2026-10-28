import Foundation

enum Recurrence: String, CaseIterable, Identifiable {
    case none, daily, weekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Never"
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }
}

/// How a chore repeats. `weekdayMask` has bit (weekday - 1) set for each chosen
/// weekday, using `Calendar` numbering (1 = Sunday ... 7 = Saturday).
struct RecurrenceRule: Equatable {
    var kind: Recurrence = .none
    var weekdayMask: Int = 0

    var isRepeating: Bool { kind != .none }

    var weekdays: Set<Int> {
        get { Set((1...7).filter { weekdayMask & (1 << ($0 - 1)) != 0 }) }
        set { weekdayMask = newValue.reduce(0) { $0 | (1 << ($1 - 1)) } }
    }

    /// The first due date strictly after `base` (a start-of-day date).
    func nextDate(after base: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: base)
        switch kind {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: start)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: start)
        case .weekly:
            let chosen = weekdays
            if chosen.isEmpty { return calendar.date(byAdding: .day, value: 7, to: start) }
            for offset in 1...7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                if chosen.contains(calendar.component(.weekday, from: day)) { return day }
            }
            return nil
        }
    }

    func summary(calendar: Calendar = .current) -> String {
        switch kind {
        case .none: return "Doesn't repeat"
        case .daily: return "Every day"
        case .monthly: return "Every month"
        case .weekly:
            let chosen = weekdays
            guard !chosen.isEmpty else { return "Every week" }
            let names = calendar.shortWeekdaySymbols
            return "Every " + chosen.sorted().map { names[$0 - 1] }.joined(separator: ", ")
        }
    }
}
