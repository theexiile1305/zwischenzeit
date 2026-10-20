import SwiftUI

/// Colour category of a treatment. The live API may later supply colours per
/// treatment type. Until then CalendarFeature maps treatment types onto these.
public enum TreatmentStyle: String, CaseIterable, Sendable {
    case kg, mld, mldLong, device, heat, cold, other, blocker

    public var fill: Color {
        switch self {
        case .kg: DS.Color.eventKg
        case .mld: DS.Color.eventMld
        case .mldLong: DS.Color.eventMldLong
        case .device: DS.Color.eventDevice
        case .heat: DS.Color.eventHeat
        case .cold: DS.Color.eventCold
        case .other: DS.Color.eventOther
        case .blocker: DS.Color.eventBlocker
        }
    }

    public var edge: Color {
        switch self {
        case .kg: DS.Color.eventKgStrong
        case .mld: DS.Color.eventMldStrong
        case .mldLong: DS.Color.eventMldStrong
        case .device: DS.Color.eventDeviceStrong
        case .heat: DS.Color.eventHeatStrong
        case .cold, .other: DS.Color.eventHeatStrong.opacity(0.6)
        case .blocker: DS.Color.text.opacity(0.4)
        }
    }

    public var foreground: Color { self == .blocker ? DS.Color.onEventBlocker : DS.Color.onEvent }
}

/// `arrived`: checked in at reception (not "done").
public enum EventStatus: Sendable { case planned, arrived, cancelled }

/// What a card shows. Built by CalendarFeature from a domain `Appointment`.
public struct EventCardModel: Identifiable, Hashable, Sendable {
    public let id: String
    public var time: String                 // "09:40"
    public var title: String                // patient name, or blocker title
    public var session: String?             // "9/10"
    public var treatment: String            // "Lymphdrainage Teil 30 Minuten"
    public var note: String?                // third line
    public var shortCode: String?           // "KGG"
    public var style: TreatmentStyle
    public var status: EventStatus
    public var isSeries: Bool
    public var room: String?                // "Raum 2"
    public var isLastSession: Bool          // n == m: prescription used up
    public var isPast: Bool                 // already over: drawn dimmed

    public init(id: String, time: String, title: String, session: String? = nil, treatment: String,
                note: String? = nil, shortCode: String? = nil, style: TreatmentStyle,
                status: EventStatus = .planned, isSeries: Bool = false, room: String? = nil,
                isLastSession: Bool = false, isPast: Bool = false) {
        self.id = id; self.time = time; self.title = title; self.session = session
        self.treatment = treatment; self.note = note; self.shortCode = shortCode
        self.style = style; self.status = status; self.isSeries = isSeries
        self.room = room; self.isLastSession = isLastSession; self.isPast = isPast
    }

    public var accessibilityText: String {
        var parts = [time, title]
        if let session, let slash = session.firstIndex(of: "/") {
            parts.append("Termin \(session[..<slash]) von \(session[session.index(after: slash)...])")
        }
        parts.append(treatment)
        if let room { parts.append(room) }
        if let note { parts.append(note) }
        if isLastSession { parts.append("letzte Behandlung des Rezepts") }
        if isSeries { parts.append("Serientermin") }
        switch status {
        case .arrived: parts.append("ist da")
        case .cancelled: parts.append("abgesagt")
        case .planned: break
        }
        return parts.joined(separator: ", ")
    }
}

public struct EventCard: View {
    public enum Density: Sendable { case full, compact }

    let model: EventCardModel
    let density: Density

    public init(_ model: EventCardModel, density: Density = .full) {
        self.model = model
        self.density = density
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(model.style.edge).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.Space.s2) {
                    // Narrow cards keep only time and name; the glyphs come back with room to spare.
                    if model.isSeries && density == .full { Image(systemName: "infinity").font(.caption2.weight(.bold)) }
                    // Time and session stay. Only the name truncates.
                    Group {
                        Text(model.time).lineLimit(1).layoutPriority(2)
                        Text(model.title).lineLimit(1).truncationMode(.tail).layoutPriority(1)
                        if let session = model.session, density == .full { Text(session).lineLimit(1).layoutPriority(1) }
                    }
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                    if density == .compact {
                        // Short slots: the treatment gets whatever room is left on the one line.
                        // All or nothing: a lone first letter helps nobody.
                        ViewThatFits(in: .horizontal) {
                            Text(model.treatment).font(.caption2).lineLimit(1).fixedSize().opacity(0.85)
                            Color.clear.frame(width: 0, height: 0)
                        }
                    }
                    Spacer(minLength: 0)
                    if model.isLastSession && density == .full { Image(systemName: "flag.checkered").font(.caption2.weight(.bold)) }
                    if density == .full { statusGlyph }
                }
                if density == .full {
                    HStack(spacing: DS.Space.s4) {
                        Text(model.treatment).font(.caption2).lineLimit(2)
                        Spacer(minLength: 0)
                        if let room = model.room {
                            Text(room).font(.caption2.weight(.medium)).lineLimit(1).layoutPriority(1)
                        }
                        if let code = model.shortCode {
                            Text(code).font(.caption2.weight(.bold).italic())
                        }
                    }
                    if let note = model.note {
                        Text(note).font(.caption2).lineLimit(1)
                    }
                }
            }
            .strikethrough(model.status == .cancelled)
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s2)
        }
        .foregroundStyle(model.style.foreground)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: DS.Layout.eventMinHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(model.style.fill)
        .overlay { if model.status == .cancelled { DSHatch().opacity(0.18) } }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))
        .opacity(model.isPast && model.status != .cancelled ? 0.6 : 1)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityText)
        .accessibilityHint("Öffnet Details")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var statusGlyph: some View {
        switch model.status {
        case .arrived: Image(systemName: "person.fill.checkmark").font(.caption2)
        case .cancelled: Image(systemName: "xmark.circle").font(.caption2)
        case .planned: EmptyView()
        }
    }
}

/// Month view chip: time + treatment, no patient name.
public struct MonthChip: View {
    let time: String
    let treatment: String
    let style: TreatmentStyle

    public init(time: String, treatment: String, style: TreatmentStyle) {
        self.time = time
        self.treatment = treatment
        self.style = style
    }

    public var body: some View {
        Text("\(time) \(treatment)")
            .font(.caption2).monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(style.foreground)
            .padding(.horizontal, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.xs).fill(style.fill))
    }
}
