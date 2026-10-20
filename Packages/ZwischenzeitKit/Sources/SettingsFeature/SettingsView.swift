import DesignSystem
import DocumentationFeature
import Domain
import Observation
import SwiftUI
import WatchSync
import WatchUI

/// Persists the watch settings (no patient data) and reports changes.
@MainActor @Observable
public final class WatchSettingsModel {
    public var settings: WatchSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            onChange(settings)
        }
    }

    private let defaults: UserDefaults
    private let key = "watchSettings" // UserDefaults key name, not a secret. mobsf-ignore: ios_hardcoded_secret
    private let onChange: @MainActor (WatchSettings) -> Void

    public init(defaults: UserDefaults = .standard, onChange: @escaping @MainActor (WatchSettings) -> Void = { _ in }) {
        self.defaults = defaults
        self.onChange = onChange
        if let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(WatchSettings.self, from: data) {
            settings = s
        } else {
            settings = WatchSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}

/// What the settings screen shows about the paired watch.
public struct WatchStatus: Equatable, Sendable {
    public var isPaired: Bool
    public var isAppInstalled: Bool
    public var lastSync: Date?
    public var error: String?

    public init(isPaired: Bool, isAppInstalled: Bool, lastSync: Date? = nil, error: String? = nil) {
        self.isPaired = isPaired
        self.isAppInstalled = isAppInstalled
        self.lastSync = lastSync
        self.error = error
    }
}

/// Settings: watch options, account info and logout.
public struct SettingsView: View {
    @Bindable var model: WatchSettingsModel
    let status: WatchStatus
    let session: Session?
    let owner: Employee?
    /// The device has no passcode, so the app lock cannot protect anything.
    let showsPasscodeWarning: Bool
    let onSignOut: () -> Void

    public init(model: WatchSettingsModel, status: WatchStatus, session: Session?, owner: Employee? = nil,
                showsPasscodeWarning: Bool = false, onSignOut: @escaping () -> Void) {
        self.model = model
        self.status = status
        self.session = session
        self.owner = owner
        self.showsPasscodeWarning = showsPasscodeWarning
        self.onSignOut = onSignOut
    }

    public var body: some View {
        Form {
            if showsPasscodeWarning {
                Section {
                    DSBanner("Gerät ohne Code: Termine sind nicht geschützt. Bitte in den iPhone-Einstellungen einen Code festlegen.",
                             kind: .error)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section {
                Toggle("Nächsten Termin auf der Watch anzeigen", isOn: $model.settings.isEnabled)
                Group {
                    Picker("Vorlaufzeit", selection: $model.settings.leadMinutes) {
                        ForEach(WatchSettings.leadTimeOptions, id: \.self) { Text(WatchSettings.leadTimeTitle($0)).tag($0) }
                    }
                    Picker("Namen auf der Watch", selection: $model.settings.nameDisplay) {
                        ForEach(WatchSettings.NameDisplay.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Behandlung anzeigen", isOn: $model.settings.showTreatment)
                        .disabled(model.settings.nameDisplay == .hidden)
                    Toggle("Raum anzeigen", isOn: $model.settings.showRoom)
                    Toggle("Haptik bei Hinweis", isOn: $model.settings.haptic)
                }
                .disabled(!model.settings.isEnabled)
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("Die Watch zeigt vor jedem Termin, was als Nächstes ansteht. Patienten können das Display am Handgelenk sehen, deshalb sind standardmäßig nur Initialen sichtbar.")
            }

            Section("Vorschau") {
                WatchNextCard(item: previewItem, now: previewNow, isEnabled: model.settings.isEnabled)
                    .padding(DS.Space.s12)
                    .frame(maxWidth: 220, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.lg).fill(Color.black))
                    .environment(\.colorScheme, .dark)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }

            Section("Status") {
                LabeledContent("Watch gekoppelt", value: status.isPaired ? "Ja" : "Nein")
                LabeledContent("Watch-App installiert", value: status.isAppInstalled ? "Ja" : "Nein")
                LabeledContent("Letzter Abgleich", value: status.lastSync.map { PracticeCalendar.format($0, "dMMMHHmm") } ?? "–")
                if let error = status.error {
                    Text(error).foregroundStyle(DS.Color.danger)
                } else if !status.isPaired {
                    Text("Keine Apple Watch mit diesem iPhone gekoppelt.").font(.footnote).foregroundStyle(DS.Color.textMuted)
                } else if !status.isAppInstalled {
                    Text("Die Watch-App über die Watch-App auf dem iPhone installieren.").font(.footnote).foregroundStyle(DS.Color.textMuted)
                }
            }

            #if !os(watchOS)
            Section {
                NavigationLink {
                    SnippetManagerView()
                } label: {
                    Label("Textbausteine", systemImage: "text.badge.plus")
                }
            } header: {
                Text("Dokumentation")
            } footer: {
                Text("Kurze Texte, die beim Dokumentieren mit einem Tipp eingefügt werden.")
            }
            #endif

            Section("Konto") {
                if let owner {
                    LabeledContent("Kalender von", value: owner.displayName)
                }
                if let session {
                    LabeledContent("Angemeldet als", value: session.employee.displayName)
                    LabeledContent("Praxis", value: session.practiceName)
                }
                Button("Abmelden", role: .destructive, action: onSignOut)
            }
        }
        .navigationTitle("Einstellungen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // Fake preview data, shaped by the current settings.
    private var previewNow: Date { PracticeCalendar.date(on: .now, hour: 9, minute: 28) }

    private var previewItem: UpcomingItem {
        let s = model.settings
        let title: String
        switch s.nameDisplay {
        case .full: title = "Anna Bergmann"
        case .initials: title = "A. B."
        case .hidden: title = "Krankengymnastik"
        }
        let start = PracticeCalendar.date(on: .now, hour: 9, minute: 40)
        return UpcomingItem(id: "preview", start: start, end: start.addingTimeInterval(20 * 60), title: title,
                            subtitle: s.showTreatment && s.nameDisplay != .hidden ? "Krankengymnastik" : nil,
                            room: s.showRoom ? "Raum 2" : nil, style: .kg, session: "4/6")
    }
}
