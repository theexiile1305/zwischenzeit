import Foundation
import Observation
import OSLog
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Counts and error codes only - never patient names, free text or payload contents.
private let watchSyncLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Zwischenzeit", category: "WatchSync")

public enum WatchSyncConstants {
    /// From the `AppGroupID` Info.plist key, which project.yml fills from `APP_GROUP_ID` (Config/*.xcconfig).
    public static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? "group.zwischenzeit"
    public static let payloadKey = "payload"
    public static let notificationCategory = "NEXT_APPOINTMENT"
}

/// How reading the on-disk payload turned out. Distinguishes "never synced" (`.missing`)
/// from "synced, but the file is unreadable right now" (`.unreadable` - e.g. the watch is
/// locked, since the payload uses complete file protection) from a decode failure
/// (`.corrupt` - e.g. a payload shape from a phone app version skew).
public enum UpcomingLoadResult: Equatable, Sendable {
    case missing
    case unreadable
    case corrupt
    case loaded(UpcomingPayload)
}

/// Watch-side persistence of the last payload in the App Group, so the widget
/// extension can read it. File protection: complete.
public enum UpcomingStore {
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WatchSyncConstants.appGroup)?
            .appendingPathComponent("upcoming.json")
    }

    public static func load(at customURL: URL? = nil) -> UpcomingPayload? {
        if case .loaded(let payload) = loadResult(at: customURL) { return payload }
        return nil
    }

    public static func loadResult(at customURL: URL? = nil) -> UpcomingLoadResult {
        guard let url = customURL ?? url else { return .missing }
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        guard let payload = try? UpcomingPayload.decode(data) else { return .corrupt }
        return .loaded(payload)
    }

    public static func save(_ payload: UpcomingPayload, at customURL: URL? = nil) throws {
        guard let url = customURL ?? url else { return }
        do {
            #if os(macOS)
            try UpcomingPayload.encode(payload).write(to: url, options: .atomic)
            #else
            try UpcomingPayload.encode(payload).write(to: url, options: [.atomic, .completeFileProtection])
            #endif
        } catch {
            watchSyncLog.error("UpcomingStore.save failed: \((error as NSError).domain, privacy: .public)/\((error as NSError).code, privacy: .public)")
            throw error
        }
    }

    public static func clear(at customURL: URL? = nil) {
        guard let url = customURL ?? url else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            let nsError = error as NSError
            guard nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileNoSuchFileError else {
                watchSyncLog.error("UpcomingStore.clear failed: \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public)")
                return
            }
        }
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
        // The watch app (installed separately from the phone app, often slower) may not be
        // ready yet. Stash the payload so it goes out once sessionWatchStateDidChange reports
        // it's ready, instead of dropping this sync permanently.
        guard session.isPaired, session.isWatchAppInstalled else {
            pending = payload
            return
        }
        do {
            let data = try UpcomingPayload.encode(payload)
            try session.updateApplicationContext([WatchSyncConstants.payloadKey: data])
            lastSent = payload.generatedAt
            lastError = nil
        } catch {
            lastError = "Abgleich mit der Watch fehlgeschlagen."
            watchSyncLog.error("PhoneWatchBridge.send failed: \((error as NSError).domain, privacy: .public)/\((error as NSError).code, privacy: .public)")
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
        if let error {
            watchSyncLog.error("PhoneWatchBridge activation error: \((error as NSError).domain, privacy: .public)/\((error as NSError).code, privacy: .public)")
        }
        Task { @MainActor in
            apply(paired: paired, installed: installed)
            if let pending, paired, installed { self.pending = nil; send(pending) }
        }
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired, installed = session.isWatchAppInstalled
        Task { @MainActor in
            apply(paired: paired, installed: installed)
            if let pending, paired, installed { self.pending = nil; send(pending) }
        }
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
    /// How the last on-disk read went - lets the UI tell "never synced" apart from
    /// "disabled" apart from "unreadable right now" (the watch is locked).
    public private(set) var lastLoadResult: UpcomingLoadResult
    private let onPayload: @MainActor (UpcomingPayload) async -> Void

    public init(onPayload: @escaping @MainActor (UpcomingPayload) async -> Void) {
        self.onPayload = onPayload
        let result = UpcomingStore.loadResult()
        self.lastLoadResult = result
        if case .loaded(let payload) = result { self.payload = payload }
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Re-reads the App Group file. The watch app can only be foregrounded while the
    /// device is unlocked, so call this on appear/activation to clear a stale `.unreadable`
    /// left over from a background wake while locked.
    public func refreshFromDisk() {
        let result = UpcomingStore.loadResult()
        lastLoadResult = result
        if case .loaded(let payload) = result { self.payload = payload }
    }

    func receive(_ context: [String: Any]) async {
        guard let data = context[WatchSyncConstants.payloadKey] as? Data else { return }
        guard let payload = try? UpcomingPayload.decode(data) else {
            watchSyncLog.error("WatchReceiver.receive: payload decode failed")
            return
        }
        if payload.settings.isEnabled {
            do {
                try UpcomingStore.save(payload)
            } catch {
                // Logged inside UpcomingStore.save. Leave the previous on-disk payload in
                // place rather than risk a half-written file.
            }
        } else {
            // Delete first: removal doesn't need the file-protection key, so it still works
            // while locked. If the disabled sentinel then fails to save, the file is already
            // gone (reads as .missing), never the stale enabled payload.
            UpcomingStore.clear()
            try? UpcomingStore.save(payload)
        }
        self.payload = payload
        lastLoadResult = UpcomingStore.loadResult()
        await onPayload(payload)
    }

    /// Keeps a `.backgroundTask(.watchConnectivity)` wake alive while a context delivery is
    /// still in flight, so `receive(_:)` (and so `onPayload`) gets to run before the system
    /// suspends the app again - not just on the next foreground launch.
    public func waitForPendingContext(timeout: TimeInterval = 25) async {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState != .activated { session.activate() }
        let deadline = Date().addingTimeInterval(timeout)
        while session.hasContentPending, Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

extension WatchReceiver: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error {
            watchSyncLog.error("WatchReceiver activation error: \((error as NSError).domain, privacy: .public)/\((error as NSError).code, privacy: .public)")
        }
        let context = session.receivedApplicationContext
        guard !context.isEmpty, let data = context[WatchSyncConstants.payloadKey] as? Data else { return }
        Task { @MainActor in await receive([WatchSyncConstants.payloadKey: data]) }
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context[WatchSyncConstants.payloadKey] as? Data else { return }
        Task { @MainActor in await receive([WatchSyncConstants.payloadKey: data]) }
    }
}
#endif
