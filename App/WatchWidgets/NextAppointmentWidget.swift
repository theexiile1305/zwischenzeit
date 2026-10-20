import Domain
import SwiftUI
import WatchSync
import WatchUI
import WidgetKit

/// Complication: next appointment on the watch face and in the Smart Stack.
struct NextAppointmentEntry: TimelineEntry {
    let date: Date
    let next: UpcomingItem?
    let isEnabled: Bool
    let relevance: TimelineEntryRelevance?
}

struct NextAppointmentProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAppointmentEntry {
        let start = Date.now.addingTimeInterval(12 * 60)
        return NextAppointmentEntry(date: .now, next: UpcomingItem(id: "p", start: start, end: start.addingTimeInterval(1200),
                                                                    title: "A. B.", subtitle: "Krankengymnastik", style: .kg),
                                    isEnabled: true, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAppointmentEntry) -> Void) {
        completion(entries(now: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAppointmentEntry>) -> Void) {
        completion(Timeline(entries: entries(now: .now), policy: .never)) // the watch app reloads on each sync
    }

    private func entries(now: Date) -> [NextAppointmentEntry] {
        guard let payload = UpcomingStore.load() else {
            return [NextAppointmentEntry(date: now, next: nil, isEnabled: false, relevance: nil)]
        }
        return WidgetTimelinePlanner.entries(payload, now: now).map { e in
            let soon = e.next.map { $0.start.timeIntervalSince(e.date) < Double(payload.settings.leadMinutes * 60 + 600) } ?? false
            return NextAppointmentEntry(date: e.date, next: e.next, isEnabled: payload.settings.isEnabled,
                                        relevance: TimelineEntryRelevance(score: soon ? 100 : 10))
        }
    }
}

struct NextAppointmentWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextAppointmentEntry

    var body: some View {
        Group {
            if !entry.isEnabled {
                Image(systemName: "applewatch.slash").accessibilityLabel("Termin-Anzeige ist aus")
            } else if let item = entry.next {
                content(item)
            } else {
                Label("Keine Termine", systemImage: "calendar").accessibilityLabel("Heute keine weiteren Termine")
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private func content(_ item: UpcomingItem) -> some View {
        let time = PracticeCalendar.time(item.start)
        switch family {
        case .accessoryCircular:
            // Timer-driven, so the ring fills on the face between timeline entries.
            ProgressView(timerInterval: window(item), countsDown: false) {
                Image(systemName: "calendar")
            } currentValueLabel: {
                Text(time).monospacedDigit()
            }
            .progressViewStyle(.circular)
            .accessibilityLabel(sentence(item))
        case .accessoryCorner:
            Text(time).monospacedDigit().widgetAccentable()
                .widgetLabel {
                    ProgressView(timerInterval: window(item), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                }
                .accessibilityLabel(sentence(item))
        case .accessoryInline:
            // Redacted on a locked watch and on the always-on face when complication data is hidden.
            Text([time, item.title, item.subtitle].compactMap { $0 }.joined(separator: " · "))
                .privacySensitive()
        default:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(time).monospacedDigit().widgetAccentable()
                    Group {
                        if item.start > entry.date {
                            Text(item.start, style: .relative)
                        } else {
                            Text("noch ") + Text(timerInterval: entry.date...max(item.end, entry.date), countsDown: true)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .font(.headline)
                Text(item.title).font(.body).lineLimit(1).privacySensitive()
                let details = [item.subtitle, item.room, item.session].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .privacySensitive()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sentence(item))
        }
    }

    /// Fills up over the last hour before the start, then over the appointment itself.
    private func window(_ item: UpcomingItem) -> ClosedRange<Date> {
        item.start > entry.date
            ? item.start.addingTimeInterval(-3600)...item.start
            : item.start...max(item.end, item.start.addingTimeInterval(1))
    }

    private func sentence(_ item: UpcomingItem) -> String {
        ["Nächster Termin \(PracticeCalendar.time(item.start))", item.title, item.subtitle, item.room].compactMap { $0 }.joined(separator: ", ")
    }
}

@main
struct NextAppointmentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextAppointment", provider: NextAppointmentProvider()) { entry in
            NextAppointmentWidgetView(entry: entry)
        }
        .configurationDisplayName("Nächster Termin")
        .description("Zeigt den nächsten Termin aus dem Kalender.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}
