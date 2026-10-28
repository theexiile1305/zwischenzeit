import SwiftUI

// MARK: - DSDayPill

/// One day in the week strip: weekday, date, and a dot when there is something booked.
public struct DSDayPill: View {
    let weekday: String
    let day: String
    let isSelected: Bool
    let isToday: Bool
    let hasAppointments: Bool
    let accessibilityText: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 56

    public init(weekday: String, day: String, isSelected: Bool, isToday: Bool, hasAppointments: Bool,
                accessibilityText: String, action: @escaping () -> Void) {
        self.weekday = weekday
        self.day = day
        self.isSelected = isSelected
        self.isToday = isToday
        self.hasAppointments = hasAppointments
        self.accessibilityText = accessibilityText
        self.action = action
    }

    private var foreground: Color {
        if isSelected { return DS.Color.onAccent }
        return isToday ? DS.Color.accent : DS.Color.text
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s2) {
                Text(weekday)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(isSelected ? DS.Color.onAccent : DS.Color.textMuted)
                Text(day)
                    .font(.body.weight(isSelected || isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(foreground)
                Circle()
                    .fill(isSelected ? DS.Color.onAccent : DS.Color.accent)
                    .frame(width: 5, height: 5)
                    .opacity(hasAppointments ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(isSelected ? DS.Color.accent : .clear))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - DSBadge

/// Small capsule label on rows and cards: "6/6", "Letzte Behandlung", "Raum 2".
public struct DSBadge: View {
    public enum Tone: Sendable { case neutral, accent, warning, danger, success }

    let title: String
    let systemImage: String?
    let tone: Tone

    public init(_ title: String, systemImage: String? = nil, tone: Tone = .neutral) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: DS.Space.s2) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(title).monospacedDigit().lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, DS.Space.s8)
        .padding(.vertical, DS.Space.s2)
        .background(Capsule().fill(background))
        .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .neutral: DS.Color.text
        case .accent: DS.Color.accent
        case .warning: DS.Color.onWarning
        case .danger: DS.Color.danger
        case .success: DS.Color.success
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: DS.Color.surface
        case .accent: DS.Color.accent.opacity(0.12)
        case .warning: DS.Color.warning
        case .danger: DS.Color.danger.opacity(0.12)
        case .success: DS.Color.success.opacity(0.14)
        }
    }
}

// MARK: - DSProgressSegments

/// "Behandlung n von m" as m segments, the first n filled.
public struct DSProgressSegments: View {
    let current: Int
    let total: Int
    let tint: Color

    public init(current: Int, total: Int, tint: Color = DS.Color.accent) {
        self.current = current
        self.total = total
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: DS.Space.s4) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(i < current ? tint : DS.Color.gridLineStrong)
                    .frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Behandlung \(current) von \(total)")
    }
}

// MARK: - DSHatch

/// Diagonal stripes: cancelled cards and not-bookable bands. A second signal besides colour.
public struct DSHatch: View {
    let color: Color
    let spacing: CGFloat
    let lineWidth: CGFloat

    public init(color: Color = DS.Color.cancelledHatch, spacing: CGFloat = 8, lineWidth: CGFloat = 3) {
        self.color = color
        self.spacing = spacing
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Check-in state next to a patient name. Reception sets it; the app only shows it.
/// `waiting` is the loud one: the patient is here and her slot is now.
public struct DSCheckInBadge: View {
    public enum State: Sendable { case waiting, arrived, overdue }

    let state: State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var pulse = false

    public init(_ state: State) { self.state = state }

    public var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .waiting:
            Label("Ist da", systemImage: "person.fill.checkmark")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Color.onSuccess)
                .padding(.horizontal, DS.Space.s8)
                .padding(.vertical, DS.Space.s2)
                .background(Capsule().fill(DS.Color.success))
                .background {
                    // A slow ring, so the eye finds it in a long list. Off with Reduce Motion.
                    Capsule().stroke(DS.Color.success, lineWidth: 2)
                        .scaleEffect(pulse ? 1.25 : 1)
                        .opacity(pulse ? 0 : 0.5)
                }
                .fixedSize()
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
                }
        case .arrived:
            Image(systemName: "person.fill.checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Color.success)
        case .overdue:
            Label("Noch nicht da", systemImage: "clock")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Color.textMuted)
                .padding(.horizontal, DS.Space.s8)
                .padding(.vertical, DS.Space.s2)
                .overlay(Capsule().strokeBorder(DS.Color.border, lineWidth: 1))
                .fixedSize()
        }
    }

    private var accessibilityText: String {
        switch state {
        case .waiting: "Patient ist da und wartet"
        case .arrived: "Patient ist da"
        case .overdue: "Noch nicht eingetroffen"
        }
    }
}
