import DesignSystem
import Domain
import SwiftUI

/// Month overview: compact chips per day, tap a day to open it.
struct MonthView: View {
    let model: CalendarModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let maxChips = 5
    /// A full day for the load bar: 8 hours of treatment.
    private let fullDayMinutes = 8 * 60

    private var columnCount: Int { model.showWeekend ? 7 : 5 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: columnCount), spacing: 1) {
                    ForEach(model.days, id: \.self) { day in
                        cell(day)
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
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Circle().fill(today ? DS.Color.accent : .clear))
                }
                if sizeClass == .regular {
                    ForEach(items.prefix(maxChips), id: \.id) { a in
                        let card = model.card(for: a)
                        MonthChip(time: card.time, treatment: card.treatment, style: card.style)
                            .opacity(a.status == .cancelled ? 0.5 : 1)
                    }
                    if items.count > maxChips {
                        Text("+\(items.count - maxChips) weitere")
                            .font(.caption2)
                            .foregroundStyle(DS.Color.textMuted)
                    }
                } else {
                    load(summary)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, minHeight: sizeClass == .regular ? 120 : 76, alignment: .topLeading)
            .background(inMonth ? DS.Color.bg : DS.Color.surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PracticeCalendar.format(day, "EEEEdMMMM")), \(summary.treatments) Termine")
        .accessibilityHint("Zeigt diesen Tag")
    }

    /// Phone: the number of treatments and a bar for how full the day is.
    @ViewBuilder private func load(_ summary: AgendaSummary) -> some View {
        if summary.treatments > 0 {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text("\(summary.treatments)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.text)
                GeometryReader { geo in
                    Capsule().fill(DS.Color.gridLine)
                        .overlay(alignment: .leading) {
                            Capsule().fill(DS.Color.accent)
                                .frame(width: geo.size.width * min(CGFloat(summary.bookedMinutes) / CGFloat(fullDayMinutes), 1))
                        }
                }
                .frame(height: 4)
            }
        }
    }
}
