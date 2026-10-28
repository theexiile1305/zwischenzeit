import DesignSystem
import Domain
import SwiftUI

/// Week and day grid: time column, day columns, cards, bands, now line.
struct TimeGridView: View {
    @Bindable var model: CalendarModel
    let onOpen: (AppointmentID) -> Void

    @State private var didScrollToNow = false
    /// Live pinch value; committed to the model on release so a pinch does not
    /// invalidate every observer of `CalendarModel` on each frame.
    @State private var pinchHeight: CGFloat?
    @State private var pinchBase: CGFloat?

    private var minuteHeight: CGFloat { pinchHeight ?? model.minuteHeight }

    private var hours: [Int] { Array(model.dayStartHour...model.dayEndHour) }
    private var gridMinutes: Int { (model.dayEndHour - model.dayStartHour) * 60 }

    var body: some View {
        VStack(spacing: 0) {
            if model.mode != .day {
                header
                Divider().overlay(DS.Color.gridLineStrong)
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        timeColumn
                        ForEach(model.days, id: \.self) { day in
                            DayColumn(model: model, day: day, minuteHeight: minuteHeight, onOpen: onOpen)
                                .frame(maxWidth: .infinity)
                                .overlay(alignment: .leading) { Rectangle().fill(DS.Color.gridLine).frame(width: 1) }
                        }
                    }
                    .frame(height: CGFloat(gridMinutes) * minuteHeight)
                    .padding(.top, DS.Space.s8)
                    .padding(.bottom, DS.Space.s48)
                }
                .onAppear { scrollToNow(proxy) }
                .onChange(of: model.mode) { didScrollToNow = false; scrollToNow(proxy) }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase ?? model.minuteHeight
                        pinchBase = base
                        pinchHeight = min(max(base * value.magnification, DS.Layout.minuteHeightMin), DS.Layout.minuteHeightMax)
                    }
                    .onEnded { _ in
                        if let pinchHeight { model.minuteHeight = pinchHeight }
                        pinchHeight = nil
                        pinchBase = nil
                    }
            )
        }
        .background(DS.Color.bg)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: DS.Layout.timeColumnWidth, height: 1)
            ForEach(model.days, id: \.self) { day in
                Button {
                    model.go(to: day, mode: .day)
                } label: {
                    Text(headerTitle(day))
                        .font(.subheadline.weight(model.isToday(day) ? .bold : .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(model.isToday(day) ? DS.Color.accent : DS.Color.text)
                        .frame(maxWidth: .infinity, minHeight: max(DS.Layout.dayHeaderHeight, 44))
                        .background(model.isToday(day) ? DS.Color.todayTint : .clear)
                }
                .buttonStyle(.plain)
                .disabled(model.mode == .day)
                .accessibilityLabel(PracticeCalendar.format(day, "EEEEdMMMM"))
                .accessibilityHint(model.mode == .day ? "" : "Zeigt diesen Tag")
            }
        }
        .background(DS.Color.surface)
    }

    private func headerTitle(_ day: Date) -> String {
        if model.mode == .day { return PracticeCalendar.format(day, "EEEEdMMMM") }
        let weekday = PracticeCalendar.format(day, "EEE").replacingOccurrences(of: ".", with: "")
        return "\(weekday) \(PracticeCalendar.calendar.component(.day, from: day))."
    }

    // MARK: Time column

    private var timeColumn: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(hours, id: \.self) { hour in
                ForEach([0, 30], id: \.self) { minute in
                    let offset = CGFloat((hour - model.dayStartHour) * 60 + minute)
                    if hour < model.dayEndHour || minute == 0 {
                        Text(minute == 0 ? "\(hour) Uhr" : "\(hour):30")
                            .font(.caption.weight(minute == 0 ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(DS.Color.textMuted)
                            .padding(.trailing, DS.Space.s4)
                            .offset(y: offset * minuteHeight - 7)
                            .opacity(minute == 30 && minuteHeight < 1.2 ? 0 : 1)
                    }
                }
                Color.clear.frame(height: 1).offset(y: CGFloat((hour - model.dayStartHour) * 60) * minuteHeight).id(hour)
            }
        }
        .frame(width: DS.Layout.timeColumnWidth)
        .overlay(alignment: .topTrailing) {
            if model.days.contains(where: model.isToday) { NowPill(model: model, minuteHeight: minuteHeight) }
        }
        .accessibilityHidden(true)
    }

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        guard !didScrollToNow else { return }
        didScrollToNow = true
        let hour = PracticeCalendar.calendar.component(.hour, from: model.currentDate)
        let target = min(max(hour - 1, model.dayStartHour), model.dayEndHour)
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
    }
}

/// One day column: background, bands, grid lines, cards, now line.
private struct DayColumn: View {
    let model: CalendarModel
    let day: Date
    let minuteHeight: CGFloat
    let onOpen: (AppointmentID) -> Void

    var body: some View {
        let appointments = model.appointments(on: day)
        let placed = DayLayout.place(appointments, dayStartHour: model.dayStartHour)
        let byID = Dictionary(appointments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let mh = minuteHeight

        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                (model.isToday(day) && model.mode == .week ? DS.Color.todayTint : DS.Color.bg)
                    .accessibilityHidden(true)

                ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                    // Hatched, so "not bookable" reads differently from "free".
                    ZStack {
                        DS.Color.unavailable
                        DSHatch(color: DS.Color.gridLineStrong, spacing: 10, lineWidth: 1).opacity(0.5)
                    }
                    .frame(height: CGFloat(band.count - 1) * mh)
                    .clipped()
                    .offset(y: CGFloat(band.lowerBound) * mh)
                    .allowsHitTesting(false)
                }

                GridLines(hours: model.dayEndHour - model.dayStartHour, minuteHeight: mh)
                    .allowsHitTesting(false)

                if model.mode == .day {
                    ForEach(freeGaps, id: \.id) { gap in
                        let height = CGFloat(gap.end.timeIntervalSince(gap.start) / 60) * mh
                        if case .free(let minutes) = gap.kind, height >= 24 {
                            Text("\(Countdown.duration(minutes: minutes)) frei")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DS.Color.textMuted)
                                .frame(maxWidth: .infinity, minHeight: height)
                                .frame(height: height)
                                .offset(y: CGFloat(PracticeCalendar.minuteOfDay(gap.start) - model.dayStartHour * 60) * mh)
                                .allowsHitTesting(false)
                        }
                    }
                }

                if model.state == .loading && appointments.isEmpty {
                    SkeletonCards(minuteHeight: mh)
                }

                ForEach(placed, id: \.id) { p in
                    if let a = byID[p.id] {
                        let gap = DS.Layout.eventGap
                        let width = geo.size.width / CGFloat(p.columnCount)
                        let height = CGFloat(p.height) * mh
                        Button { onOpen(a.id) } label: {
                            EventCard(model.card(for: a), density: height < 34 || width < 96 ? .compact : .full)
                        }
                        .buttonStyle(.plain)
                        .frame(width: max(width - gap, 1), height: max(height - gap, 1))
                        .clipped()
                        .offset(x: CGFloat(p.column) * width + gap / 2, y: CGFloat(p.top) * mh + gap / 2)
                    }
                }

                if model.isToday(day) { NowLine(model: model, minuteHeight: minuteHeight) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(PracticeCalendar.format(day, "EEEEdMMMM")), \(appointments.count) Termine")
    }

    private var freeGaps: [AgendaEntry] {
        model.agendaEntries(on: day).filter {
            if case .free(let minutes) = $0.kind { return minutes >= 20 }
            return false
        }
    }

    private var bands: [ClosedRange<Int>] {
        model.blocked.compactMap { DayLayout.band($0, on: day, dayStartHour: model.dayStartHour, dayEndHour: model.dayEndHour) }
    }
}

private struct GridLines: View {
    let hours: Int
    let minuteHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            for half in 0...(hours * 2) {
                let y = CGFloat(half * 30) * minuteHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(half.isMultiple(of: 2) ? DS.Color.gridLineStrong : DS.Color.gridLine), lineWidth: half.isMultiple(of: 2) ? 1 : 0.5)
            }
        }
    }
}

private struct NowLine: View {
    let model: CalendarModel
    let minuteHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let minute = PracticeCalendar.minuteOfDay(model.currentDate) - model.dayStartHour * 60
            if minute >= 0 && minute <= (model.dayEndHour - model.dayStartHour) * 60 {
                HStack(spacing: 0) {
                    Circle().fill(DS.Color.nowLine).frame(width: 8, height: 8)
                    Rectangle().fill(DS.Color.nowLine).frame(height: 2)
                }
                .offset(x: -4, y: CGFloat(minute) * minuteHeight - 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

/// "09:28" on the time column, at the now line.
private struct NowPill: View {
    let model: CalendarModel
    let minuteHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let now = model.currentDate
            let minute = PracticeCalendar.minuteOfDay(now) - model.dayStartHour * 60
            if minute >= 0 && minute <= (model.dayEndHour - model.dayStartHour) * 60 {
                Text(PracticeCalendar.time(now))
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.onDanger)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(DS.Color.nowLine))
                    .offset(y: CGFloat(minute) * minuteHeight - 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct SkeletonCards: View {
    let minuteHeight: CGFloat

    var body: some View {
        ForEach([60, 90, 140, 200, 260], id: \.self) { top in
            RoundedRectangle(cornerRadius: DS.Radius.xs)
                .fill(DS.Color.surface)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.xs).strokeBorder(DS.Color.border))
                .frame(height: 20 * minuteHeight - DS.Layout.eventGap)
                .padding(.horizontal, DS.Layout.eventGap)
                .offset(y: CGFloat(top) * minuteHeight)
        }
        .accessibilityHidden(true)
    }
}
