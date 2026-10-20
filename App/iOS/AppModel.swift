import BackgroundTasks
import CalendarFeature
import Domain
import Foundation
import LiveAPI
import LocalAuthentication
import MockAPI
import Observation
import SettingsFeature
import WatchSync

/// App-wide state: session, reference data, calendar, watch sync, app lock.
@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case launching, signedOut, signedIn }

    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist (`$(PRODUCT_BUNDLE_IDENTIFIER).watchsync`).
    static let backgroundTaskID = (Bundle.main.bundleIdentifier ?? "Zwischenzeit") + ".watchsync"

    private(set) var phase: Phase = .launching
    private(set) var session: Session?
    /// Whose calendar is shown: the signed-in employee.
    var owner: Employee? { session?.employee }
    private(set) var reference = ReferenceData()
    private(set) var calendar: CalendarModel?
    private(set) var signInError: String?
    /// Password accepted; waiting for the TOTP code.
    private(set) var needsMFA = false
    private(set) var isLocked = false

    let api: any TToolsAPI
    let now: () -> Date
    let watchBridge = PhoneWatchBridge()
    private(set) var watchSettings: WatchSettingsModel!
    private var backgroundedAt: Date?

    /// Debug-only launch arguments (screenshots, UI tests). Release builds ignore them all.
    nonisolated static var launchArguments: [String] {
        #if DEBUG
        ProcessInfo.processInfo.arguments
        #else
        []
        #endif
    }

    /// False on a device without a passcode: the app lock then has nothing to unlock with.
    var deviceHasPasscode: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    private let usesMockAPI: Bool

    init() {
        let args = Self.launchArguments
        // -fixedNow 2026-10-14T09:28:00+02:00 freezes the clock for screenshots and UI tests.
        let fixed = args.firstIndex(of: "-fixedNow").flatMap { i in
            args.indices.contains(i + 1) ? ISO8601DateFormatter().date(from: args[i + 1]) : nil
        }
        let now: () -> Date = fixed.map { d in { d } } ?? { .now }
        self.now = now
        // -mockAPI (implied by -fixedNow) uses fake seed data for screenshots and UI tests.
        usesMockAPI = args.contains("-mockAPI") || fixed != nil
        if usesMockAPI {
            self.api = MockTToolsAPI(now: now(), signedIn: !args.contains("-signedOut"))
        } else {
            Self.clearKeychainAfterReinstall()
            self.api = LiveTToolsAPI()
        }
        self.watchSettings = WatchSettingsModel { [weak self] _ in self?.syncWatch() }
        // -watchEnabled turns the watch feature on (UI tests and simulator checks).
        if args.contains("-watchEnabled") { watchSettings.settings.isEnabled = true }
    }

    var watchStatus: WatchStatus {
        WatchStatus(isPaired: watchBridge.isPaired, isAppInstalled: watchBridge.isWatchAppInstalled,
                    lastSync: watchBridge.lastSent, error: watchBridge.lastError)
    }

    // MARK: Session

    func start() async {
        do {
            if let s = try await api.restoreSession() {
                // A cold start with a stored session asks for Face ID / the passcode first.
                if !usesMockAPI, deviceHasPasscode { isLocked = true }
                try await enter(s)
                if isLocked { await unlock() }
            } else {
                phase = .signedOut
            }
        } catch {
            phase = .signedOut
        }
    }

    func signIn(practice: String, username: String, password: String) async {
        signInError = nil
        do {
            switch try await api.signIn(practice: practice, username: username, password: password) {
            case .signedIn(let s): try await enter(s)
            case .mfaRequired: needsMFA = true
            }
        } catch {
            signInError = Self.signInMessage(error)
        }
    }

    func submitMFA(code: String) async {
        signInError = nil
        do {
            try await enter(try await api.submitMFA(code: code))
            needsMFA = false
        } catch let e as APIError where e == .mfaInvalid {
            signInError = e.message
        } catch {
            // Locked, rate-limited or the temporary token expired: back to the password step.
            needsMFA = false
            signInError = Self.signInMessage(error)
        }
    }

    func cancelMFA() {
        needsMFA = false
        signInError = nil
    }

    private static func signInMessage(_ error: Error) -> String {
        guard let e = error as? APIError else { return "Anmeldung fehlgeschlagen." }
        return e == .unauthorized ? "Anmeldung fehlgeschlagen. Bitte Zugangsdaten prüfen." : e.message
    }

    func signOut() async {
        await api.signOut()
        watchBridge.send(.disabled(at: now()))
        session = nil
        calendar = nil
        reference = ReferenceData()
        phase = .signedOut
    }

    private func enter(_ session: Session) async throws {
        self.session = session
        reference = try await ReferenceData.load(from: api)
        let model = CalendarModel(api: api, employeeID: session.employee.id, reference: reference, now: now)
        model.onLoaded = { [weak self] in self?.syncWatch() }
        calendar = model
        phase = .signedIn
    }

    // MARK: Watch

    /// Sends today's and tomorrow's appointments, formatted per the watch settings.
    func syncWatch() {
        Task { await performWatchSync() }
    }

    func performWatchSync() async {
        let settings = watchSettings.settings
        guard let owner, settings.isEnabled else {
            watchBridge.send(.disabled(at: now()))
            return
        }
        let today = PracticeCalendar.startOfDay(now())
        let range = DateInterval(start: today, end: PracticeCalendar.calendar.date(byAdding: .day, value: 2, to: today)!)
        guard let appointments = try? await api.appointments(for: owner.id, in: range) else { return }
        watchBridge.send(UpcomingBuilder.build(appointments, reference: reference, settings: settings, now: now()))
    }

    func registerBackgroundSync() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskID, using: nil) { task in
            Task { @MainActor in
                self.scheduleBackgroundSync()
                await self.performWatchSync()
                task.setTaskCompleted(success: true)
            }
        }
    }

    func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: App lock

    /// The Keychain outlives an uninstall. A fresh install must not pick up an old session.
    private static func clearKeychainAfterReinstall() {
        let key = "didLaunchBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        KeychainTokenStore().clear()
        UserDefaults.standard.set(true, forKey: key)
    }

    func didEnterBackground() {
        backgroundedAt = .now
        scheduleBackgroundSync()
    }

    func didBecomeActive() {
        defer { backgroundedAt = nil }
        if let backgroundedAt, Date.now.timeIntervalSince(backgroundedAt) > 5 * 60, phase == .signedIn {
            isLocked = true
            Task { await unlock() }
        }
        if phase == .signedIn { syncWatch() }
    }

    func unlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false // no passcode on the device: nothing to unlock with
            return
        }
        if (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Termine anzeigen")) == true {
            isLocked = false
        }
    }
}
