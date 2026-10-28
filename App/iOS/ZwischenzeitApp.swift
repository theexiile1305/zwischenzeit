import AppointmentFeature
import CalendarFeature
import DesignSystem
import Domain
import SettingsFeature
import SwiftUI

@main
struct ZwischenzeitApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()
    @State private var capture = ScreenCaptureMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {}

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task {
                    await model.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background: model.didEnterBackground()
                    case .active: model.didBecomeActive()
                    default: break
                    }
                }
                .overlay {
                    // Privacy cover in the app switcher, during screen recording or mirroring, and the Face ID lock.
                    if scenePhase != .active || model.isLocked || capture.isCaptured {
                        LockCover(isLocked: model.isLocked && !capture.isCaptured) { Task { await model.unlock() } }
                    }
                }
        }
        // Registers and runs the watch background sync. The scene modifier (rather than
        // BGTaskScheduler.register from a view's .task) guarantees the system registers the
        // handler at the right point in app launch.
        .backgroundTask(.appRefresh(AppModel.backgroundTaskID)) {
            await model.handleBackgroundRefresh()
        }
    }
}

enum Route: Hashable {
    case appointment(AppointmentID)
    case settings
}

struct RootView: View {
    let model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path: [Route] = []
    @State private var sidebarSelection: SidebarItem? = .calendar
    @State private var didPickInitialMode = false
    @State private var didApplyRoute = false

    enum SidebarItem: Hashable { case calendar, settings }

    var body: some View {
        content
            // Split View, Slide Over and rotation swap the layout. Settings is a sidebar item in one
            // and a pushed route in the other, so carry it across; appointments live in `path` for both.
            .onChange(of: sizeClass) { _, newClass in
                if newClass == .regular {
                    if path.first == .settings {
                        path.removeFirst()
                        sidebarSelection = .settings
                    }
                } else if sidebarSelection == .settings {
                    sidebarSelection = .calendar
                    path.insert(.settings, at: 0)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .launching:
            ProgressView().controlSize(.large)
        case .signedOut:
            LoginView(model: model)
        case .signedIn:
            if let calendar = model.calendar {
                if sizeClass == .regular {
                    splitView(calendar)
                } else {
                    NavigationStack(path: $path) {
                        CalendarScreen(model: calendar,
                                       onOpen: { path.append(.appointment($0)) },
                                       onSettings: { path.append(.settings) })
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationDestination(for: Route.self, destination: destination)
                    }
                    .onAppear {
                        // The phone opens on the day as a list; the grids are one tap away.
                        if !didPickInitialMode { calendar.mode = LaunchOptions.mode ?? .agenda; didPickInitialMode = true }
                        if let route = LaunchOptions.route(calendar), path.isEmpty { path = [route] }
                    }
                    .onChange(of: calendar.state) {
                        guard calendar.state == .loaded, !didApplyRoute else { return }
                        didApplyRoute = true
                        if path.isEmpty, let route = LaunchOptions.route(calendar) { path = [route] }
                    }
                }
            }
        }
    }

    private func splitView(_ calendar: CalendarModel) -> some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Label("Kalender", systemImage: "calendar").tag(SidebarItem.calendar)
                Label("Einstellungen", systemImage: "gearshape").tag(SidebarItem.settings)
            }
            .navigationTitle(model.session?.practiceName ?? "Zwischenzeit")
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if sidebarSelection == .settings {
                        settings
                    } else {
                        CalendarScreen(model: calendar, onOpen: { path.append(.appointment($0)) })
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
                .navigationDestination(for: Route.self, destination: destination)
            }
        }
        // A size-class change sets the selection too and may push .settings; keep that route.
        .onChange(of: sidebarSelection) { path.removeAll { $0 != .settings } }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .appointment(let id):
            AppointmentDetailView(model: AppointmentDetailModel(id: id, api: model.api, reference: model.reference,
                                                                ownerID: model.owner?.id, now: model.now),
                                  startEditing: LaunchOptions.opensDocumentation)
        case .settings:
            settings
        }
    }

    private var settings: some View {
        SettingsView(model: model.watchSettings, status: model.watchStatus, session: model.session, owner: model.owner,
                     showsPasscodeWarning: !model.deviceHasPasscode) {
            path.removeAll()
            Task { await model.signOut() }
        }
    }
}

/// Debug launch arguments for screenshots and UI tests:
/// `-calendarMode agenda|day|week|month`, `-route settings|firstAppointment|documentation`.
enum LaunchOptions {
    private static var args: [String] { AppModel.launchArguments }
    private static func value(_ key: String) -> String? {
        args.firstIndex(of: key).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }

    /// `-route documentation`: the first appointment with the documentation editor open.
    static var opensDocumentation: Bool { value("-route") == "documentation" }

    static var mode: CalendarMode? { value("-calendarMode").flatMap(CalendarMode.init(rawValue:)) }

    @MainActor static func route(_ calendar: CalendarModel) -> Route? {
        switch value("-route") {
        case "settings": return .settings
        case "firstAppointment", "documentation":
            let now = calendar.currentDate
            return calendar.appointments.first { $0.kind == .treatment && $0.end > now }.map { .appointment($0.id) }
        default: return nil
        }
    }
}

/// Third-party keyboards are disabled: they can send keystrokes (passwords, documentation text) off the device.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        if extensionPointIdentifier == .keyboard { return false }
        return true
    }
}

/// True while the screen is recorded, mirrored or shown via AirPlay.
@MainActor @Observable
final class ScreenCaptureMonitor {
    private(set) var isCaptured = false

    init() {
        update()
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIScreen.capturedDidChangeNotification) {
                self?.update()
            }
        }
    }

    private func update() {
        isCaptured = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.traitCollection.sceneCaptureState == .active }
    }
}

struct LockCover: View {
    let isLocked: Bool
    let onUnlock: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var lockIconSize: CGFloat = 44

    var body: some View {
        ZStack {
            DS.Color.bg.ignoresSafeArea()
            VStack(spacing: DS.Space.s16) {
                Image(systemName: "lock.fill").font(.system(size: lockIconSize)).foregroundStyle(DS.Color.textMuted)
                    .accessibilityHidden(true)
                Text("Termine sind ausgeblendet").font(.headline).foregroundStyle(DS.Color.text)
                if isLocked {
                    DSButton("Entsperren", action: onUnlock)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
