import DesignSystem
import Domain
import SwiftUI

/// The calendar screen: header, week strip and the agenda, day, week or month view. Read-only: no create or edit actions.
public struct CalendarScreen: View {
    @Bindable var model: CalendarModel
    let onOpen: (AppointmentID) -> Void
    let onSettings: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDatePicker = false
    @State private var showZoom = false

    public init(model: CalendarModel, onOpen: @escaping (AppointmentID) -> Void, onSettings: (() -> Void)? = nil) {
        self.model = model
        self.onOpen = onOpen
        self.onSettings = onSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if model.mode == .agenda || model.mode == .day {
                weekStrip
            }
            Divider().overlay(DS.Color.gridLine)
            if case .failed(let error) = model.state {
                HStack {
                    DSBanner(LocalizedStringKey(error.message), kind: error == .offline ? .offline : .error)
                    DSButton("Erneut", variant: .plain) { model.reload() }
                }
                .padding(.horizontal, DS.Space.s8)
                .padding(.vertical, DS.Space.s4)
            }
            // One page per period: a new anchor replaces the page and it slides in from the side we moved towards.
            content
                .id(model.anchor)
                .transition(pageTransition)
                .mask { Rectangle().ignoresSafeArea(edges: .bottom) } // clips the slide, not the home-indicator area
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            let dx = value.translation.width, dy = value.translation.height
                            guard abs(dx) > 50, abs(dx) > abs(dy) else { return }
                            model.step(dx < 0 ? 1 : -1)
                        }
                )
                .accessibilityAction(named: "Vorheriger Zeitraum") { model.step(-1) }
                .accessibilityAction(named: "Nächster Zeitraum") { model.step(1) }
        }
        .background(DS.Color.bg)
        .task { if model.state == .idle { model.reload() } }
        .onChange(of: sizeClass, initial: true) { model.weekDayLimit = sizeClass == .compact ? 3 : nil }
        .sheet(isPresented: $showDatePicker) { datePickerSheet }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.anchor)
        .sensoryFeedback(.selection, trigger: model.anchor)
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let edge: Edge = model.navigationDirection >= 0 ? .trailing : .leading
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity), removal: .opacity)
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .agenda:
            AgendaView(model: model, onOpen: onOpen)
        case .day, .week:
            TimeGridView(model: model, onOpen: onOpen)
                .overlay {
                    if model.state == .loaded && model.days.allSatisfy({ model.appointments(on: $0).isEmpty }) {
                        DSEmptyState(model.mode == .day ? "Keine Termine an diesem Tag" : "Keine Termine in dieser Woche")
                            .allowsHitTesting(false)
                    }
                }
        case .month:
            MonthView(model: model)
        }
    }

    // MARK: Header

    private var header: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Title gets its own line; the controls wrap below instead of squeezing it.
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    titleButton
                    HStack(spacing: DS.Space.s4) { headerControls }
                }
            } else {
                HStack(alignment: .center, spacing: DS.Space.s4) {
                    titleButton
                    Spacer(minLength: DS.Space.s4)
                    headerControls
                }
            }
        }
        .padding(.leading, DS.Space.s16)
        .padding(.trailing, DS.Space.s8)
        .frame(minHeight: DS.Layout.toolbarHeight)
        .background(DS.Color.bg)
    }

    private var titleButton: some View {
        Button { showDatePicker = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DS.Space.s4) {
                        Text(model.headerTitle)
                            .font(.title2.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DS.Color.textMuted)
                    }
                    if let subtitle = model.headerSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(DS.Color.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .monospacedDigit()
                .foregroundStyle(DS.Color.text)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.accessibilityTitle)
            .accessibilityHint("Datum wählen")
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var headerControls: some View {

            if model.state == .loading {
                ProgressView().controlSize(.small).accessibilityLabel("Lädt")
            }

            if !model.isShowingToday {
                Button("Heute") { model.goToToday() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Color.accent)
                    .padding(.horizontal, DS.Space.s12)
                    .frame(height: 32)
                    .background(Capsule().fill(DS.Color.accent.opacity(0.12)))
                    .frame(minHeight: 44)
                    .accessibilityHint("Springt zum heutigen Tag")
            }

            if model.mode == .week || model.mode == .month {
                plainIcon("Zurück", "chevron.left") { model.step(-1) }
                plainIcon("Weiter", "chevron.right") { model.step(1) }
            }

            if sizeClass == .regular {
                Picker("Ansicht", selection: $model.mode) {
                    ForEach(CalendarMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            Menu {
                if sizeClass != .regular {
                    Picker("Ansicht", selection: $model.mode) {
                        ForEach(CalendarMode.allCases) { Label($0.title, systemImage: icon(for: $0)).tag($0) }
                    }
                }
                Toggle(isOn: $model.showWeekend) { Label("Wochenende anzeigen", systemImage: "calendar.day.timeline.left") }
                if model.mode == .day || model.mode == .week {
                    Button { showZoom = true } label: { Label("Zeilenhöhe", systemImage: "arrow.up.and.down.text.horizontal") }
                }
                Button { model.reload() } label: { Label("Aktualisieren", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: icon(for: model.mode))
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Ansicht: \(model.mode.title)")
            .accessibilityHint("Ansicht und Optionen")
            .popover(isPresented: $showZoom) { zoomPopover }

            if let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Einstellungen")
            }
    }

    private func plainIcon(_ label: LocalizedStringKey, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(label))
    }

    // MARK: Week strip

    private var weekStrip: some View {
        HStack(spacing: DS.Space.s4) {
            ForEach(model.stripDays, id: \.self) { day in
                DSDayPill(
                    weekday: PracticeCalendar.format(day, "EEE").replacingOccurrences(of: ".", with: ""),
                    day: "\(PracticeCalendar.calendar.component(.day, from: day))",
                    isSelected: PracticeCalendar.calendar.isDate(day, inSameDayAs: model.anchor),
                    isToday: model.isToday(day),
                    hasAppointments: model.hasAppointments(on: day),
                    accessibilityText: [PracticeCalendar.relativeDayName(day, now: model.currentDate),
                                        PracticeCalendar.format(day, "EEEEdMMMM"),
                                        model.hasAppointments(on: day) ? "\(model.appointments(on: day).filter { $0.kind == .treatment && $0.status != .cancelled }.count) Termine" : nil]
                        .compactMap { $0 }.joined(separator: ", ")
                ) {
                    model.go(to: day)
                }
            }
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.bottom, DS.Space.s8)
        .background(DS.Color.bg)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > 50, abs(value.translation.width) > abs(value.translation.height) else { return }
                    DS.Motion.perform(reduce: reduceMotion) { model.stepWeek(value.translation.width < 0 ? 1 : -1) }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Woche")
        .accessibilityAction(named: "Vorherige Woche") { model.stepWeek(-1) }
        .accessibilityAction(named: "Nächste Woche") { model.stepWeek(1) }
    }

    private func icon(for mode: CalendarMode) -> String {
        switch mode {
        case .agenda: "list.bullet.rectangle"
        case .day: "calendar.day.timeline.leading"
        case .week: "calendar"
        case .month: "square.grid.3x3"
        }
    }

    private var zoomPopover: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Text("Zeilenhöhe").font(.headline)
            Slider(value: $model.minuteHeight, in: DS.Layout.minuteHeightMin...DS.Layout.minuteHeightMax) {
                Text("Zeilenhöhe")
            } minimumValueLabel: {
                Image(systemName: "minus.magnifyingglass")
            } maximumValueLabel: {
                Image(systemName: "plus.magnifyingglass")
            }
            Text("Tipp: Mit zwei Fingern im Raster zoomen.").font(.footnote).foregroundStyle(DS.Color.textMuted)
        }
        .padding(DS.Space.s16)
        .frame(minWidth: 280)
        .presentationCompactAdaptation(.popover)
    }

    @State private var pickedDate = Date.now

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Datum", selection: $pickedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, PracticeCalendar.locale)
                .environment(\.timeZone, PracticeCalendar.timeZone)
                .padding()
                .navigationTitle("Datum wählen")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showDatePicker = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Anzeigen") { model.go(to: pickedDate); showDatePicker = false }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear { pickedDate = model.anchor }
    }
}
