import DesignSystem
import Domain
import SwiftUI
import UserNotifications
import WatchSync
import WatchUI
import WidgetKit

@main
struct ZwischenzeitWatchApp: App {
    @State private var receiver = WatchReceiver { payload in
        NotificationScheduler.reschedule(for: payload)
        WidgetCenter.shared.reloadAllTimelines()
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
    }
}

/// Watch home: next appointment with countdown, then the rest of today.
struct WatchHomeView: View {
    let receiver: WatchReceiver

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let payload = receiver.payload
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    WatchNextCard(item: payload?.next(at: now), now: now,
                                  isStale: payload?.isStale(at: now) ?? false,
                                  generatedAt: payload?.generatedAt,
                                  isEnabled: payload?.settings.isEnabled ?? false)
                    if let payload, payload.settings.isEnabled {
                        let rest = payload.remainingToday(after: now)
                        let left = payload.treatmentsLeftToday(at: now)
                        if !rest.isEmpty {
                            Text(left == 1 ? "Heute noch 1 Termin" : "Heute noch \(left) Termine")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
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
    }
}

/// Heads-up notifications: local notifications scheduled on the watch, so they fire on the wrist
/// even while the phone is in use. The phone schedules none (no duplicates).
enum NotificationScheduler {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func reschedule(for payload: UpcomingPayload) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for planned in NotificationPlanner.plan(payload, now: .now) {
            let item = planned.item
            let content = UNMutableNotificationContent()
            let minutes = Int((item.start.timeIntervalSince(planned.fireDate) / 60).rounded())
            content.title = minutes > 0 ? "In \(minutes) Min.: \(PracticeCalendar.time(item.start))" : "Jetzt: \(PracticeCalendar.time(item.start))"
            content.body = [item.title, item.subtitle, item.room].compactMap { $0 }.joined(separator: " · ")
            content.categoryIdentifier = WatchSyncConstants.notificationCategory
            content.interruptionLevel = .timeSensitive
            if payload.settings.haptic { content.sound = .default }
            let components = PracticeCalendar.calendar.dateComponents(in: PracticeCalendar.timeZone, from: planned.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: "next-\(item.id)", content: content, trigger: trigger))
        }
    }
}
