import SwiftUI

// MARK: - DSButton

public struct DSButton: View {
    public enum Variant: Sendable { case primary, plain }

    let title: LocalizedStringKey
    let variant: Variant
    let isLoading: Bool
    let action: () -> Void

    public init(_ title: LocalizedStringKey, variant: Variant = .primary, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.variant = variant
        self.isLoading = isLoading
        self.action = action
    }

    private var fill: Color {
        variant == .primary ? DS.Color.accent : .clear
    }

    private var foreground: Color {
        variant == .primary ? DS.Color.onAccent : DS.Color.accent
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(foreground) }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, DS.Space.s16)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(fill))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isLoading)
        .accessibilityValue(isLoading ? Text("lädt") : Text(""))
    }
}

// MARK: - DSEmptyState / DSBanner / status pill

public struct DSEmptyState: View {
    let title: LocalizedStringKey
    let systemImage: String

    public init(_ title: LocalizedStringKey = "Keine Termine", systemImage: String = "calendar.badge.checkmark") {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(spacing: DS.Space.s8) {
            Image(systemName: systemImage).font(.system(size: 40)).foregroundStyle(DS.Color.textMuted)
            Text(title).font(.headline).foregroundStyle(DS.Color.textMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

public struct DSBanner: View {
    public enum Kind: Sendable { case error, offline }

    let message: LocalizedStringKey
    let kind: Kind

    public init(_ message: LocalizedStringKey, kind: Kind) {
        self.message = message
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: DS.Space.s8) {
            Image(systemName: icon)
            Text(message)
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(kind == .offline ? DS.Color.textMuted : DS.Color.onDanger)
        .padding(DS.Space.s12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(kind == .offline ? DS.Color.surface : DS.Color.danger))
        .accessibilityElement(children: .combine)
    }

    private var icon: String { kind == .error ? "exclamationmark.triangle.fill" : "wifi.slash" }
}

public struct DSStatusPill: View {
    public enum Status: Sendable { case open, completed, cancelled }

    let status: Status
    public init(_ status: Status) { self.status = status }

    public var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, DS.Space.s8)
            .padding(.vertical, DS.Space.s2)
            .background(Capsule().fill(background))
    }

    private var title: LocalizedStringKey {
        switch status {
        case .open: "Offen"
        case .completed: "Abgeschlossen"
        case .cancelled: "Storniert"
        }
    }
    private var background: Color {
        switch status {
        case .open: DS.Color.warning
        case .completed: DS.Color.success
        case .cancelled: DS.Color.danger
        }
    }
    private var foreground: Color {
        switch status {
        case .open: DS.Color.onWarning
        case .completed: DS.Color.onSuccess
        case .cancelled: DS.Color.onDanger
        }
    }
}

// MARK: - Shared style

struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: configuration.isPressed)
    }
}
