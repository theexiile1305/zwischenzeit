import DesignSystem
import Domain
import SwiftUI

/// "Heute": the working day as a list. On today it opens with the next patient,
/// folds away what is already over, and shows free gaps and the pause between rows.
struct AgendaView: View {
    let model: CalendarModel
    let onOpen: (AppointmentID) -> Void

    @State private var showPast = false

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let day = model.anchor
            let now = model.currentDate
            let entries = model.agendaEntries(on: day)
            let isToday = model.isToday(day)
            let past = isToday ? entries.filter { $0.end <= now } : []
            let next = isToday ? model.nextUp : nil
            // The next-up card already shows that one appointment.
            let upcoming = (isToday ? entries.filter { $0.end > now } : entries).filter { $0.id != next?.id.raw }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !entries.isEmpty {
                        SummaryLine(summary: AgendaBuilder.summary(entries), isToday: isToday)
                            .padding(.horizontal, DS.Space.s16)
                            .padding(.bottom, DS.Space.s12)
                    }

                    if let next {
                        NextUpCard(appointment: next, model: model, now: now) { onOpen(next.id) }
                            .padding(.horizontal, DS.Space.s16)
                            .padding(.bottom, DS.Space.s16)
                    } else if isToday && entries.contains(where: { $0.appointment?.kind == .treatment }) {
                        DayDoneCard()
                            .padding(.horizontal, DS.Space.s16)
                            .padding(.bottom, DS.Space.s16)
                    }

                    if !past.isEmpty {
                        PastToggle(count: past.compactMap(\.appointment).count, isExpanded: $showPast)
                        if showPast { rows(past, now: now, nextID: nil) }
                    }
                    rows(upcoming, now: now, nextID: next?.id)
                }
                .padding(.top, DS.Space.s8)
                .padding(.bottom, DS.Space.s48)
            }
            .overlay { emptyOrLoading(entries) }
        }
        .refreshable { await model.refresh() }
        .onChange(of: model.anchor) { showPast = false }
        .background(DS.Color.bg)
    }

    @ViewBuilder private func rows(_ entries: [AgendaEntry], now: Date, nextID: AppointmentID?) -> some View {
        ForEach(entries) { entry in
            switch entry.kind {
            case .appointment(let a):
                Button { onOpen(a.id) } label: {
                    AgendaRow(appointment: a, model: model, checkIn: a.checkIn(now: now), isPast: a.end <= now,
                              isRunning: a.start <= now && a.end > now && a.status != .cancelled,
                              isNext: a.id == nextID)
                }
                .buttonStyle(RowPressStyle())
            case .free(let minutes):
                GapRow(minutes: minutes, start: entry.start)
            case .pause:
                PauseRow(start: entry.start, end: entry.end)
            }
        }
    }

    @ViewBuilder private func emptyOrLoading(_ entries: [AgendaEntry]) -> some View {
        if entries.isEmpty {
            if model.state == .loading {
                ProgressView().controlSize(.large)
            } else if model.state == .loaded {
                DSEmptyState(PracticeCalendar.isWeekend(model.anchor) ? "Wochenende – keine Termine" : "Keine Termine an diesem Tag",
                             systemImage: "sun.max")
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Summary

private struct SummaryLine: View {
    let summary: AgendaSummary
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(summary.text)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(DS.Color.textMuted)
            if isToday && summary.treatments > 0 {
                ProgressView(value: Double(summary.arrived), total: Double(summary.treatments))
                    .tint(DS.Color.success)
                    .accessibilityLabel("\(summary.arrived) von \(summary.treatments) Patienten waren schon da")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Next up

private struct NextUpCard: View {
    let appointment: Appointment
    let model: CalendarModel
    let now: Date
    let action: () -> Void

    private var isRunning: Bool { appointment.start <= now }
    private var style: TreatmentStyle { model.style(appointment) }
    private var checkIn: CheckIn { appointment.checkIn(now: now) }
    /// Green means "go and get them"; once her slot runs she is already with the patient.
    private var isWaiting: Bool { checkIn == .waiting && !isRunning }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.s12) {
                HStack {
                    Label(isRunning ? "Läuft gerade" : "Als Nächstes",
                          systemImage: isRunning ? "figure.strengthtraining.functional" : "arrow.forward.circle.fill")
                        .font(.footnote.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(DS.Color.accent)
                    Spacer()
                    Text(isRunning ? Countdown.remaining(end: appointment.end, now: now)
                                   : Countdown.text(start: appointment.start, now: now))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.text)
                }

                HStack(alignment: .top, spacing: DS.Space.s12) {
                    RoundedRectangle(cornerRadius: 2).fill(style.edge).frame(width: 5)
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        Text("\(PracticeCalendar.time(appointment.start))–\(PracticeCalendar.time(appointment.end))")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text(appointment.patient?.fullName ?? "Ohne Patient")
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                        if let badge = DSCheckInBadge.State(checkIn, isRunning: isRunning) { DSCheckInBadge(badge) }
                        Text(model.treatmentName(appointment))
                            .font(.subheadline)
                            .foregroundStyle(DS.Color.textMuted)
                        AppointmentBadges(appointment: appointment, room: model.roomName(appointment))
                            .padding(.top, DS.Space.s2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(DS.Color.textMuted)
                }
                .fixedSize(horizontal: false, vertical: true)

                if isRunning {
                    ProgressView(value: now.timeIntervalSince(appointment.start),
                                 total: max(appointment.end.timeIntervalSince(appointment.start), 1))
                        .tint(style.edge)
                }
            }
            .foregroundStyle(DS.Color.text)
            .padding(DS.Space.s16)
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg).fill(isWaiting ? DS.Color.success.opacity(0.08) : DS.Color.surface))
            // Patient is here: the card turns green, readable from across the room.
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(isWaiting ? DS.Color.success : DS.Color.accent.opacity(0.35), lineWidth: isWaiting ? 2 : 1))
            .animation(.easeInOut(duration: 0.3), value: isWaiting)
            .shadow(color: .black.opacity(DS.Shadow.card.opacity), radius: DS.Shadow.card.radius, y: DS.Shadow.card.y)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Öffnet Details")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [isRunning ? "Läuft gerade, \(Countdown.remaining(end: appointment.end, now: now))"
                               : "Als Nächstes, \(Countdown.text(start: appointment.start, now: now))",
                     "\(PracticeCalendar.time(appointment.start)) bis \(PracticeCalendar.time(appointment.end))",
                     appointment.patient?.fullName ?? "Ohne Patient", model.treatmentName(appointment)]
        switch checkIn {
        case .waiting, .arrived: parts.append("ist da")
        case .overdue: parts.append("noch nicht eingetroffen")
        case .none: break
        }
        if let room = model.roomName(appointment) { parts.append(room) }
        if let n = appointment.sessionNumber, let m = appointment.sessionsTotal { parts.append("Behandlung \(n) von \(m)") }
        if appointment.isLastSession { parts.append("letzte Behandlung des Rezepts") }
        return parts.joined(separator: ", ")
    }
}

private struct DayDoneCard: View {
    var body: some View {
        Label("Alle Termine für heute sind vorbei.", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(DS.Color.success)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s16)
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg).fill(DS.Color.success.opacity(0.1)))
    }
}

// MARK: - Rows

/// Room, n/m, first/last session, series, group, status. Shared by the card and the rows.
struct AppointmentBadges: View {
    let appointment: Appointment
    let room: String?

    var body: some View {
        HStack(spacing: DS.Space.s4) {
            if appointment.status == .cancelled {
                DSBadge("Abgesagt", systemImage: "xmark", tone: .danger)
            }
            if let room { DSBadge(room, systemImage: "door.left.hand.open") }
            if let session = appointment.sessionLabel { DSBadge(session) }
            if appointment.isLastSession {
                DSBadge("Letzte", systemImage: "flag.checkered", tone: .warning)
            } else if appointment.isFirstSession {
                DSBadge("Erste", systemImage: "sparkles", tone: .accent)
            }
            if appointment.groupID != nil { DSBadge("Gruppe", systemImage: "person.3") }
            if appointment.seriesID != nil {
                Image(systemName: "infinity").font(.caption.weight(.bold)).foregroundStyle(DS.Color.textMuted)
                    .accessibilityLabel("Serientermin")
            }
        }
    }
}

private struct AgendaRow: View {
    let appointment: Appointment
    let model: CalendarModel
    let checkIn: CheckIn
    let isPast: Bool
    let isRunning: Bool
    let isNext: Bool

    private var isBlocker: Bool { appointment.kind == .blocker }
    private var isCancelled: Bool { appointment.status == .cancelled }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(PracticeCalendar.time(appointment.start)).font(.subheadline.weight(.semibold))
                Text(PracticeCalendar.time(appointment.end)).font(.caption).foregroundStyle(DS.Color.textMuted)
            }
            .monospacedDigit()
            .frame(width: 48, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(model.style(appointment).edge)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .strikethrough(isCancelled)
                    if let badge = DSCheckInBadge.State(checkIn, isRunning: isRunning) { DSCheckInBadge(badge) }
                }
                Text(model.treatmentName(appointment))
                    .font(.subheadline)
                    .foregroundStyle(DS.Color.textMuted)
                    .lineLimit(2)
                if !isBlocker {
                    AppointmentBadges(appointment: appointment, room: model.roomName(appointment))
                        .padding(.top, DS.Space.s2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DS.Color.gridLineStrong)
                .padding(.top, DS.Space.s4)
        }
        .foregroundStyle(DS.Color.text)
        .padding(.vertical, DS.Space.s12)
        .padding(.horizontal, DS.Space.s16)
        .background {
            if isRunning || isNext {
                DS.Color.todayTint
            } else if isBlocker {
                DS.Color.unavailable.opacity(0.5)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(DS.Color.gridLine).frame(height: 0.5).padding(.leading, 76) }
        .opacity(isPast || isCancelled ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet Details")
    }

    private var title: String {
        isBlocker ? "Blockiert" : (appointment.patient?.listName ?? "Ohne Patient")
    }
}

private struct GapRow: View {
    let minutes: Int
    let start: Date

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            Text(PracticeCalendar.time(start))
                .font(.caption).monospacedDigit()
                .foregroundStyle(DS.Color.textMuted)
                .frame(width: 48, alignment: .trailing)
            Line().stroke(DS.Color.gridLineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: 4, height: 20)
            Text("\(Countdown.duration(minutes: minutes)) frei")
                .font(.footnote.weight(.medium))
                .foregroundStyle(DS.Color.textMuted)
            Spacer()
        }
        .padding(.horizontal, DS.Space.s16)
        .padding(.vertical, DS.Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ab \(PracticeCalendar.time(start)) \(Countdown.duration(minutes: minutes)) frei")
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in p.move(to: CGPoint(x: rect.midX, y: 0)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) }
        }
    }
}

private struct PauseRow: View {
    let start: Date
    let end: Date

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            Image(systemName: "cup.and.saucer.fill")
            Text("Pause")
                .font(.subheadline.weight(.semibold))
            Text("\(PracticeCalendar.time(start))–\(PracticeCalendar.time(end))")
                .font(.subheadline).monospacedDigit()
            Spacer()
            Text(Countdown.duration(minutes: Int(end.timeIntervalSince(start) / 60)))
                .font(.footnote).monospacedDigit()
        }
        .foregroundStyle(DS.Color.textMuted)
        .padding(.horizontal, DS.Space.s16)
        .padding(.vertical, DS.Space.s12)
        .background {
            ZStack {
                DS.Color.unavailable.opacity(0.6)
                DSHatch(color: DS.Color.gridLineStrong, spacing: 10, lineWidth: 1).opacity(0.6)
            }
        }
        .padding(.vertical, DS.Space.s4)
        .accessibilityElement(children: .combine)
    }
}

private struct PastToggle: View {
    let count: Int
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            DS.Motion.perform(reduce: reduceMotion) { isExpanded.toggle() }
        } label: {
            HStack(spacing: DS.Space.s8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(isExpanded ? "Frühere Termine ausblenden" : (count == 1 ? "1 früherer Termin" : "\(count) frühere Termine"))
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .foregroundStyle(DS.Color.accent)
            .padding(.horizontal, DS.Space.s16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "ausgeklappt" : "eingeklappt")
    }
}

private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.Color.gridLine : .clear)
    }
}

extension DSCheckInBadge.State {
    /// A running slot shows the quiet check: she is with the patient, nothing to act on.
    init?(_ checkIn: CheckIn, isRunning: Bool) {
        switch checkIn {
        case .waiting: self = isRunning ? .arrived : .waiting
        case .arrived: self = .arrived
        case .overdue: self = .overdue
        case .none: return nil
        }
    }
}
