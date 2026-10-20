import DesignSystem
import Domain
import SwiftUI
import WatchSync

/// Top card of the watch home, also the live preview in the iPhone settings.
public struct WatchNextCard: View {
    let item: UpcomingItem?
    let now: Date
    let isStale: Bool
    let generatedAt: Date?
    let isEnabled: Bool

    public init(item: UpcomingItem?, now: Date, isStale: Bool = false, generatedAt: Date? = nil, isEnabled: Bool = true) {
        self.item = item
        self.now = now
        self.isStale = isStale
        self.generatedAt = generatedAt
        self.isEnabled = isEnabled
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if !isEnabled {
                Label("Aus", systemImage: "applewatch.slash").font(.headline)
                Text("In der iPhone-App unter Einstellungen aktivieren.").font(.footnote).foregroundStyle(.secondary)
            } else if let item {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.start > now ? "Als Nächstes" : "Läuft")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer(minLength: DS.Space.s4)
                    countdown(item)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.accent)
                }
                HStack(alignment: .top, spacing: DS.Space.s8) {
                    RoundedRectangle(cornerRadius: 2).fill(item.treatmentStyle.fill).frame(width: 4)
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("\(PracticeCalendar.time(item.start))–\(PracticeCalendar.time(item.end))")
                            .font(.title3.weight(.semibold)).monospacedDigit()
                        Text(item.title).font(.headline).lineLimit(2).privacySensitive()
                        if item.isCheckedIn {
                            Label("Ist da", systemImage: "person.fill.checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DS.Color.success)
                        }
                        if let subtitle = item.subtitle { Text(subtitle).font(.footnote).lineLimit(2) }
                        HStack(spacing: DS.Space.s4) {
                            if let room = item.room {
                                HStack(spacing: DS.Space.s2) { Image(systemName: "door.left.hand.open"); Text(room) }
                            }
                            if let session = item.session { Text(session).monospacedDigit() }
                            if item.isLastSession { Image(systemName: "flag.checkered").foregroundStyle(DS.Color.warning) }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if item.start <= now {
                    // Fills live, without waking the app every second.
                    ProgressView(timerInterval: item.start...max(item.end, item.start.addingTimeInterval(1)), countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(item.treatmentStyle.edge)
                }
            } else {
                Label("Heute keine weiteren Termine", systemImage: "calendar.badge.checkmark")
                    .font(.headline)
            }
            if isStale, let generatedAt {
                Text("Stand \(PracticeCalendar.time(generatedAt))").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    public static func countdown(to item: UpcomingItem, now: Date) -> String {
        Countdown.text(start: item.start, now: now)
    }

    /// Ticks by the second in the last 10 minutes before a start and while running,
    /// otherwise the minute text (the home view refreshes every minute).
    @ViewBuilder private func countdown(_ item: UpcomingItem) -> some View {
        if item.start > now, item.start.timeIntervalSince(now) <= 600 {
            Text(timerInterval: now...item.start, countsDown: true)
        } else if item.start <= now, item.end > now {
            Text(timerInterval: now...item.end, countsDown: true)
        } else {
            Text(Self.countdown(to: item, now: now))
        }
    }

    private var accessibilityText: String {
        guard isEnabled else { return "Watch-Anzeige ist aus" }
        guard let item else { return "Heute keine weiteren Termine" }
        var parts = [item.start > now ? "Nächster Termin \(Self.countdown(to: item, now: now))"
                                      : "Läuft gerade, \(Countdown.remaining(end: item.end, now: now))",
                     "\(PracticeCalendar.time(item.start)) bis \(PracticeCalendar.time(item.end))", item.title]
        if item.isCheckedIn { parts.append("ist da") }
        if let s = item.subtitle { parts.append(s) }
        if let r = item.room { parts.append(r) }
        if let session = item.session { parts.append("Behandlung \(session.replacingOccurrences(of: "/", with: " von "))") }
        if item.isLastSession { parts.append("letzte Behandlung des Rezepts") }
        if isStale, let generatedAt { parts.append("Stand \(PracticeCalendar.time(generatedAt))") }
        return parts.joined(separator: ", ")
    }
}

/// Watch home: "20 Min. frei" between two rows of the rest of the day.
public struct WatchGapRow: View {
    let minutes: Int
    public init(minutes: Int) { self.minutes = minutes }

    public var body: some View {
        Text("\(Countdown.duration(minutes: minutes)) frei")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, DS.Space.s16)
    }
}

/// Watch home list row.
public struct WatchUpcomingRow: View {
    let item: UpcomingItem
    public init(item: UpcomingItem) { self.item = item }

    public var body: some View {
        HStack(spacing: DS.Space.s8) {
            Circle().fill(item.treatmentStyle.fill).frame(width: 8, height: 8)
            Text(PracticeCalendar.time(item.start)).monospacedDigit().font(.footnote.weight(.semibold))
            Text(item.title).font(.footnote).lineLimit(1).privacySensitive()
            if item.isLastSession { Image(systemName: "flag.checkered").font(.caption2).foregroundStyle(DS.Color.warning) }
            if item.isCancelled { Image(systemName: "xmark.circle").font(.footnote) }
        }
        .strikethrough(item.isCancelled)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isCancelled ? "abgesagt" : "")
    }
}
