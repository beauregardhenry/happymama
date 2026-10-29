import WidgetKit
import SwiftUI

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            if snapshot.isParent {
                ParentWidgetView(snapshot: snapshot, family: family)
            } else if let kid = snapshot.kids.first {
                KidWidgetView(kid: kid, today: kid.today(now: entry.date), family: family)
            } else {
                EmptyWidgetView()
            }
        } else {
            EmptyWidgetView()
        }
    }
}

private struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("😊").font(.title)
            Text("Open Happy Mama to get started.").font(.caption).multilineTextAlignment(.center)
        }
    }
}

private struct KidWidgetView: View {
    let kid: WidgetSnapshot.Kid
    let today: [WidgetSnapshot.ChoreItem]
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular:
            if let progress = kid.goalProgress {
                Gauge(value: progress) { Text("pts") } currentValueLabel: { Text("\(kid.points)") }
                    .gaugeStyle(.accessoryCircularCapacity)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text("\(kid.points)").font(.headline)
                        Text("pts").font(.caption2)
                    }
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("\(kid.emoji) \(kid.points) points").font(.headline)
                Text(today.isEmpty ? "All done today!" : "\(today.count) to do today")
                if kid.streak > 0 { Text("🔥 \(kid.streak)-day streak") }
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                summary
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if today.isEmpty {
                        Text("All done! 🎉").font(.subheadline)
                    }
                    ForEach(Array(today.prefix(3).enumerated()), id: \.offset) { _, chore in
                        HStack {
                            Image(systemName: "circle").font(.caption).foregroundStyle(.secondary)
                            Text(chore.title).font(.subheadline).lineLimit(1)
                            if let time = chore.dueTimeText {
                                Text(time).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text("\(chore.points)").font(.caption.weight(.semibold)).foregroundStyle(Color.happy)
                        }
                    }
                    if today.count > 3 {
                        Text("and \(today.count - 3) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            summary
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(kid.emoji).font(.title2)
                Spacer()
                if kid.streak > 0 { Text("🔥\(kid.streak)").font(.caption.weight(.bold)).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
            Text("\(kid.points)")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.happy)
                .minimumScaleFactor(0.6)
            Text("points").font(.caption).foregroundStyle(.secondary)
            if let progress = kid.goalProgress {
                ProgressView(value: progress).tint(progress >= 1 ? Color.green : Color.happy)
            } else {
                Text(today.isEmpty ? "All done today!" : "\(today.count) to do today")
                    .font(.caption.weight(.medium))
            }
        }
    }
}

private struct ParentWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(snapshot.waitingForReview)").font(.headline)
                    Image(systemName: "checkmark.seal").font(.caption2)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(reviewText).font(.headline)
                ForEach(snapshot.kids.prefix(2), id: \.name) { kid in
                    Text("\(kid.emoji) \(kid.name): \(kid.today().count) left")
                }
            }
        case .systemMedium:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(snapshot.householdName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(reviewText).font(.caption.weight(.semibold))
                        .foregroundStyle(snapshot.waitingForReview > 0 ? Color.happy : .secondary)
                }
                ForEach(snapshot.kids.prefix(4), id: \.name) { kid in
                    HStack {
                        Text(kid.emoji)
                        Text(kid.name).font(.subheadline.weight(.medium))
                        if kid.streak > 0 { Text("🔥\(kid.streak)").font(.caption) }
                        Spacer()
                        Text(leftText(kid)).font(.caption).foregroundStyle(.secondary)
                        Text("\(kid.points) pts").font(.caption.weight(.semibold)).foregroundStyle(Color.happy)
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Color.happy)
                Spacer(minLength: 0)
                Text("\(snapshot.waitingForReview)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.happy)
                Text(snapshot.waitingForReview == 1 ? "chore to review" : "chores to review")
                    .font(.caption).foregroundStyle(.secondary)
                Text(snapshot.householdName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reviewText: String {
        snapshot.waitingForReview == 0 ? "All caught up" : "\(snapshot.waitingForReview) to review"
    }

    private func leftText(_ kid: WidgetSnapshot.Kid) -> String {
        let left = kid.today().count
        return left == 0 ? "done" : "\(left) left"
    }
}

extension WidgetSnapshot.ChoreItem {
    /// "5:00 PM" for a chore due by a time.
    var dueTimeText: String? {
        guard let dueTime, let due else { return nil }
        let calendar = Calendar.current
        return calendar.date(byAdding: .minute, value: dueTime, to: calendar.startOfDay(for: due))?
            .formatted(date: .omitted, time: .shortened)
    }
}
