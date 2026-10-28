import DesignSystem
import Domain
import SwiftUI

/// Month overview: compact chips per day, tap a day to open it.
struct MonthView: View {
    let model: CalendarModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let maxChips = 5
    @ScaledMetric(relativeTo: .caption) private var todayCircle: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var phoneCellHeight: CGFloat = 76
    @ScaledMetric(relativeTo: .caption) private var padCellHeight: CGFloat = 120

    private static let weekColumnWidth: CGFloat = 28

    private var columnCount: Int { model.showWeekend ? 7 : 5 }

    /// The visible days split into calendar weeks.
    private var weeks: [[Date]] {
        let days = model.days
        return stride(from: 0, to: days.count, by: columnCount).map { Array(days[$0..<min($0 + columnCount, days.count)]) }
    }

    /// Week number; tap opens that week.
    private func weekNumberCell(_ firstDay: Date) -> some View {
        let number = PracticeCalendar.calendar.component(.weekOfYear, from: firstDay)
        return Button {
            model.go(to: firstDay, mode: .week)
        } label: {
            Text("\(number)")
                .font(.caption2.weight(.medium)).monospacedDigit()
                .foregroundStyle(DS.Color.textMuted)
                .frame(width: Self.weekColumnWidth)
                .frame(maxHeight: .infinity)
                .background(DS.Color.surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kalenderwoche \(number)")
        .accessibilityHint("Zeigt diese Woche")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("KW").font(.caption2).foregroundStyle(DS.Color.textMuted).frame(width: Self.weekColumnWidth)
                ForEach(Array(model.days.prefix(columnCount)), id: \.self) { day in
                    Text(PracticeCalendar.format(day, "EEE"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Color.textMuted)
                        .frame(maxWidth: .infinity, minHeight: DS.Layout.dayHeaderHeight)
                }
            }
            .background(DS.Color.surface)
            .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(weeks, id: \.first) { week in
                        HStack(spacing: 1) {
                            weekNumberCell(week.first!)
                            ForEach(week, id: \.self) { day in
                                cell(day)
                            }
                        }
                    }
                }
                .background(DS.Color.gridLine)
            }
        }
        .background(DS.Color.bg)
    }

    private func cell(_ day: Date) -> some View {
        let items = model.appointments(on: day)
        let summary = AgendaBuilder.summary(model.agendaEntries(on: day))
        let inMonth = PracticeCalendar.calendar.isDate(day, equalTo: model.anchor, toGranularity: .month)
        let today = model.isToday(day)
        return Button {
            model.go(to: day, mode: .day)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack {
                    Spacer()
                    Text("\(PracticeCalendar.calendar.component(.day, from: day))")
                        .font(.caption.weight(today ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(today ? DS.Color.onAccent : (inMonth ? DS.Color.text : DS.Color.textMuted))
                        .frame(minWidth: todayCircle, minHeight: todayCircle)
                        .background(Circle().fill(today ? DS.Color.accent : .clear))
                }
                if sizeClass == .regular {
                    ForEach(items.sorted { $0.start < $1.start }.prefix(maxChips), id: \.id) { a in
                        let card = model.card(for: a)
                        MonthChip(time: card.time, treatment: card.treatment, style: card.style, isCancelled: a.status == .cancelled)
                    }
                    if items.count > maxChips {
                        Text("+\(items.count - maxChips) weitere")
                            .font(.caption2)
                            .foregroundStyle(DS.Color.textMuted)
                    }
                } else {
                    load(summary, items: items, day: day)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, minHeight: sizeClass == .regular ? padCellHeight : phoneCellHeight, alignment: .topLeading)
            .background(background(day: day, inMonth: inMonth, today: today, summary: summary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PracticeCalendar.format(day, "EEEEdMMMM")), \(summary.treatments) Termine"
            + (summary.cancelled > 0 ? ", \(summary.cancelled) abgesagt" : ""))
        .accessibilityHint("Zeigt diesen Tag")
    }

    /// Booked minutes over the minutes the practice is open that day (absences and breaks excluded).
    private func loadFraction(_ summary: AgendaSummary, on day: Date) -> Double {
        min(Double(summary.bookedMinutes) / Double(max(model.openMinutes(on: day), 1)), 1)
    }

    /// Today is tinted, busy days warm up with the load, spillover days sit back.
    private func background(day: Date, inMonth: Bool, today: Bool, summary: AgendaSummary) -> Color {
        if today { return DS.Color.todayTint }
        guard inMonth else { return DS.Color.surface }
        guard sizeClass != .regular, summary.treatments > 0 else { return DS.Color.bg }
        let fraction = loadFraction(summary, on: day)
        return DS.Color.accent.opacity(0.05 + 0.15 * fraction)
    }

    /// Phone: the number of treatments, up to three category dots, and a bar for how full the day is.
    @ViewBuilder private func load(_ summary: AgendaSummary, items: [Appointment], day: Date) -> some View {
        if summary.treatments > 0 {
            let styles = categories(items)
            let cancelled = items.filter { $0.status == .cancelled && $0.kind == .treatment }.count
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                HStack(spacing: DS.Space.s4) {
                    Text("\(summary.treatments)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.text)
                    if cancelled > 0 {
                        Image(systemName: "xmark.circle").font(.caption2).foregroundStyle(DS.Color.textMuted)
                            .accessibilityHidden(true)
                    }
                }
                HStack(spacing: 3) {
                    ForEach(styles, id: \.self) { style in
                        Circle().fill(style.edge).frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                GeometryReader { geo in
                    Capsule().fill(DS.Color.gridLine)
                        .overlay(alignment: .leading) {
                            Capsule().fill(DS.Color.accent)
                                .frame(width: geo.size.width * CGFloat(loadFraction(summary, on: day)))
                        }
                }
                .frame(height: 4)
            }
        }
    }

    /// The first three distinct treatment categories of the day, in time order.
    private func categories(_ items: [Appointment]) -> [TreatmentStyle] {
        var seen: [TreatmentStyle] = []
        for a in items.sorted(by: { $0.start < $1.start }) where a.kind == .treatment && a.status != .cancelled {
            let style = model.style(a)
            if !seen.contains(style) { seen.append(style) }
            if seen.count == 3 { break }
        }
        return seen
    }
}
