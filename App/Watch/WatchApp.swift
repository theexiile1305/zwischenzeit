import DesignSystem
import Domain
import OSLog
import SwiftUI
import UserNotifications
import WatchSync
import WatchUI
import WatchKit
import WidgetKit

/// Counts and error codes only - never patient names, free text or payload contents.
private let watchLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Zwischenzeit", category: "Watch")

@main
struct ZwischenzeitWatchApp: App {
    @State private var receiver: WatchReceiver

    init() {
        NotificationScheduler.configure()
        // Built in a plain init body, not as the @State property's default value: an async,
        // @MainActor-isolated closure there conflicts with the macro-synthesized initializer's
        // actor-isolation inference ("default argument cannot be both main actor-isolated and
        // @concurrent").
        _receiver = State(initialValue: WatchReceiver { payload in
            await NotificationScheduler.reschedule(for: payload)
            WidgetCenter.shared.reloadAllTimelines()
        })
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(receiver: receiver)
                .task {
                    // -skipNotificationPrompt: simulator screenshots and UI tests only.
                    #if DEBUG
                    guard !ProcessInfo.processInfo.arguments.contains("-skipNotificationPrompt") else { return }
                    #endif
                    await NotificationScheduler.requestAuthorization()
                }
        }
        .backgroundTask(.watchConnectivity) {
            // Keeps the app alive long enough to process a WatchConnectivity update that
            // arrived while the app wasn't foregrounded, so notifications/widget reload
            // without needing the user to open the app first.
            await receiver.waitForPendingContext()
        }
        WKNotificationScene(controller: NotificationController.self,
                            category: WatchSyncConstants.notificationCategory)
    }
}

/// Shows the banner and plays the haptic while the app is in the foreground, too.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Long look of the heads-up notification: the same card as the app. The item is read from the
/// App Group store by id (the payload text itself holds nothing beyond what the settings allow).
final class NotificationController: WKUserNotificationHostingController<NotificationLongLook> {
    private var itemID: String?

    override var body: NotificationLongLook { NotificationLongLook(itemID: itemID) }

    override func didReceive(_ notification: UNNotification) {
        itemID = notification.request.content.userInfo[NotificationContent.itemIDKey] as? String
    }
}

struct NotificationLongLook: View {
    let itemID: String?

    var body: some View {
        let payload = UpcomingStore.load()
        let item = payload?.items.first { $0.id == itemID }
        let now = Date.now
        WatchNextCard(item: item, now: now, isStale: payload?.isStale(at: now) ?? false,
                      generatedAt: payload?.generatedAt,
                      state: payload == nil ? .locked : .enabled)
    }
}

/// Watch home: next appointment with countdown, then the rest of today.
struct WatchHomeView: View {
    let receiver: WatchReceiver
    @Environment(\.scenePhase) private var scenePhase

    var displayState: WatchDisplayState {
        switch receiver.lastLoadResult {
        case .missing, .corrupt: return .neverSynced
        case .unreadable: return .locked
        case .loaded(let payload): return payload.settings.isEnabled ? .enabled : .disabled
        }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let payload = receiver.payload
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    WatchNextCard(item: payload?.next(at: now), now: now,
                                  isStale: payload?.isStale(at: now) ?? false,
                                  generatedAt: payload?.generatedAt,
                                  state: displayState)
                    if let payload, payload.settings.isEnabled {
                        let rest = payload.remainingToday(after: now)
                        let left = payload.treatmentsLeftToday(at: now)
                        if !rest.isEmpty {
                            Text(left == 1 ? "Heute noch 1 Termin" : "Heute noch \(left) Termine")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(zip(rest.indices, rest)), id: \.1.id) { i, item in
                                let previousEnd = i == rest.startIndex ? payload.next(at: now)?.end : rest[i - 1].end
                                if let previousEnd, case let gap = Int(item.start.timeIntervalSince(previousEnd) / 60), gap >= 15 {
                                    WatchGapRow(minutes: gap)
                                }
                                WatchUpcomingRow(item: item)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Termine")
        }
        .onAppear { receiver.refreshFromDisk() }
        .onChange(of: scenePhase) { _, phase in
            // The app can only be foregrounded while the device is unlocked, so this clears
            // a stale `.unreadable` left over from a background wake while locked.
            if phase == .active { receiver.refreshFromDisk() }
        }
    }
}

/// Heads-up notifications: local notifications scheduled on the watch, so they fire on the wrist
/// even while the phone is in use. The phone schedules none (no duplicates).
enum NotificationScheduler {
    /// Registers the category and the foreground delegate.
    @MainActor static func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationPresenter.shared
        let category = UNNotificationCategory(
            identifier: WatchSyncConstants.notificationCategory, actions: [], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    static func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            watchLog.error("requestAuthorization failed: \((error as NSError).domain, privacy: .public)/\((error as NSError).code, privacy: .public)")
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        watchLog.info("notification authorizationStatus=\(settings.authorizationStatus.rawValue, privacy: .public)")
    }

    static func reschedule(for payload: UpcomingPayload) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for planned in NotificationPlanner.plan(payload, now: .now) {
            let item = planned.item
            let content = UNMutableNotificationContent()
            let minutes = Int((item.start.timeIntervalSince(planned.fireDate) / 60).rounded())
            content.title = NotificationContent.title(for: item, leadMinutes: minutes)
            content.body = NotificationContent.body(for: item)
            content.userInfo = NotificationContent.userInfo(for: item)
            content.categoryIdentifier = WatchSyncConstants.notificationCategory
            content.threadIdentifier = "appointments"
            content.interruptionLevel = .timeSensitive
            if payload.settings.haptic { content.sound = .default }
            let components = PracticeCalendar.calendar.dateComponents(in: PracticeCalendar.timeZone, from: planned.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "next-\(item.id)", content: content, trigger: trigger)
            await withCheckedContinuation { continuation in
                center.add(request) { error in
                    if let error {
                        watchLog.error("notification add failed: \((error as NSError).domain, privacy: .public)/\((error as NSError).code, privacy: .public)")
                    }
                    continuation.resume()
                }
            }
        }
    }
}
