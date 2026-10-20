import Foundation
import Observation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

public enum WatchSyncConstants {
    /// From the `AppGroupID` Info.plist key, which project.yml fills from `APP_GROUP_ID` (Config/*.xcconfig).
    public static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? "group.zwischenzeit"
    public static let payloadKey = "payload"
    public static let notificationCategory = "NEXT_APPOINTMENT"
}

/// Watch-side persistence of the last payload in the App Group, so the widget
/// extension can read it. File protection: complete.
public enum UpcomingStore {
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WatchSyncConstants.appGroup)?
            .appendingPathComponent("upcoming.json")
    }

    public static func load() -> UpcomingPayload? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? UpcomingPayload.decode(data)
    }

    public static func save(_ payload: UpcomingPayload) throws {
        guard let url else { return }
        #if os(macOS)
        try UpcomingPayload.encode(payload).write(to: url, options: .atomic)
        #else
        try UpcomingPayload.encode(payload).write(to: url, options: [.atomic, .completeFileProtection])
        #endif
    }

    public static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

#if os(iOS)
/// Phone side: activates WCSession and sends the latest payload.
@MainActor @Observable
public final class PhoneWatchBridge: NSObject {
    public private(set) var isPaired = false
    public private(set) var isWatchAppInstalled = false
    public private(set) var lastSent: Date?
    public private(set) var lastError: String?

    private var pending: UpcomingPayload?

    public override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public func send(_ payload: UpcomingPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = payload
            return
        }
        apply(paired: session.isPaired, installed: session.isWatchAppInstalled)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        do {
            let data = try UpcomingPayload.encode(payload)
            try session.updateApplicationContext([WatchSyncConstants.payloadKey: data])
            lastSent = payload.generatedAt
            lastError = nil
        } catch {
            lastError = "Abgleich mit der Watch fehlgeschlagen."
        }
    }

    private func apply(paired: Bool, installed: Bool) {
        isPaired = paired
        isWatchAppInstalled = installed
    }
}

extension PhoneWatchBridge: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let paired = session.isPaired, installed = session.isWatchAppInstalled
        Task { @MainActor in
            apply(paired: paired, installed: installed)
            if let pending { self.pending = nil; send(pending) }
        }
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired, installed = session.isWatchAppInstalled
        Task { @MainActor in apply(paired: paired, installed: installed) }
    }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
#endif

#if os(watchOS)
/// Watch side: receives payloads, stores them and calls `onPayload` (schedule
/// notifications, reload widgets).
@MainActor @Observable
public final class WatchReceiver: NSObject {
    public private(set) var payload: UpcomingPayload?
    private let onPayload: @MainActor (UpcomingPayload) -> Void

    public init(onPayload: @escaping @MainActor (UpcomingPayload) -> Void) {
        self.onPayload = onPayload
        self.payload = UpcomingStore.load()
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func receive(_ context: [String: Any]) {
        guard let data = context[WatchSyncConstants.payloadKey] as? Data,
              let payload = try? UpcomingPayload.decode(data) else { return }
        if payload.settings.isEnabled {
            try? UpcomingStore.save(payload)
        } else {
            UpcomingStore.clear()
        }
        self.payload = payload
        onPayload(payload)
    }
}

extension WatchReceiver: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        guard !context.isEmpty, let data = context[WatchSyncConstants.payloadKey] as? Data else { return }
        Task { @MainActor in receive([WatchSyncConstants.payloadKey: data]) }
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context[WatchSyncConstants.payloadKey] as? Data else { return }
        Task { @MainActor in receive([WatchSyncConstants.payloadKey: data]) }
    }
}
#endif
