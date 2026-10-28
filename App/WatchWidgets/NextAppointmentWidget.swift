import Domain
import SwiftUI
import WatchSync
import WatchUI
import WidgetKit

/// Complication: next appointment on the watch face and in the Smart Stack.
struct NextAppointmentEntry: TimelineEntry {
    let date: Date
    let next: UpcomingItem?
    let state: WatchDisplayState
    let relevance: TimelineEntryRelevance?
}

struct NextAppointmentProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAppointmentEntry {
        let start = Date.now.addingTimeInterval(12 * 60)
        return NextAppointmentEntry(date: .now, next: UpcomingItem(id: "p", start: start, end: start.addingTimeInterval(1200),
                                                                    title: "A. B.", subtitle: "Krankengymnastik", style: .kg),
                                    state: .enabled, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAppointmentEntry) -> Void) {
        completion(entries(now: .now, loadResult: UpcomingStore.loadResult()).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAppointmentEntry>) -> Void) {
        let loadResult = UpcomingStore.loadResult()
        let now = Date.now
        completion(Timeline(entries: entries(now: now, loadResult: loadResult),
                            policy: .after(WidgetTimelinePlanner.nextReloadDate(for: loadResult, now: now))))
    }

    private func entries(now: Date, loadResult: UpcomingLoadResult) -> [NextAppointmentEntry] {
        switch loadResult {
        case .missing, .corrupt:
            return [NextAppointmentEntry(date: now, next: nil, state: .neverSynced, relevance: nil)]
        case .unreadable:
            return [NextAppointmentEntry(date: now, next: nil, state: .locked, relevance: nil)]
        case .loaded(let payload):
            guard payload.settings.isEnabled else {
                return [NextAppointmentEntry(date: now, next: nil, state: .disabled, relevance: nil)]
            }
            return WidgetTimelinePlanner.entries(payload, now: now).map { e in
                let soon = e.next.map { $0.start.timeIntervalSince(e.date) < Double(payload.settings.leadMinutes * 60 + 600) } ?? false
                return NextAppointmentEntry(date: e.date, next: e.next, state: .enabled,
                                            relevance: TimelineEntryRelevance(score: soon ? 100 : 10))
            }
        }
    }
}

struct NextAppointmentWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextAppointmentEntry

    var body: some View {
        Group {
            switch entry.state {
            case .disabled:
                status("Aus", "applewatch.slash", label: "Termin-Anzeige ist aus")
            case .neverSynced:
                status("Kein Abgleich", "arrow.triangle.2.circlepath", label: "Noch kein Abgleich mit dem iPhone")
            case .locked:
                status("Entsperren", "lock.fill", label: "Uhr entsperren, um Termine zu sehen")
            case .enabled:
                if let item = entry.next {
                    content(item)
                } else {
                    Label("Keine Termine", systemImage: "calendar").accessibilityLabel("Heute keine weiteren Termine")
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Icon only where there is no room for text (circular, corner); elsewhere the icon carries a short caption.
    @ViewBuilder private func status(_ text: LocalizedStringKey, _ systemImage: String, label: LocalizedStringKey) -> some View {
        switch family {
        case .accessoryCircular, .accessoryCorner:
            Image(systemName: systemImage).accessibilityLabel(label)
        default:
            Label(text, systemImage: systemImage).accessibilityLabel(label)
        }
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
                            Text("noch \(Text(timerInterval: entry.date...max(item.end, entry.date), countsDown: true))")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .font(.headline)
                Text(item.title).font(.body).lineLimit(1).minimumScaleFactor(0.8).privacySensitive()
                let details = [item.subtitle, item.room, item.session].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
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
