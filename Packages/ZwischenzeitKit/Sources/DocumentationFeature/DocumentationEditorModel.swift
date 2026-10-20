import Domain
import Foundation
import Observation

/// Draft and save state of one documentation. The draft lives in memory only.
@MainActor @Observable
public final class DocumentationEditorModel: Identifiable {
    public enum Phase: Equatable {
        case editing
        case saving
        case failed(APIError)
        /// Someone changed it in TTools after the editor opened. Holds their text.
        case conflict(String)
    }

    public let appointment: Appointment
    public var text: String
    public private(set) var phase: Phase = .editing
    /// Bumped on success, for the haptic.
    public private(set) var savedCount = 0

    /// What the backend had when the editor opened. Saving checks it is still that.
    private(set) var base: String
    private let api: any TToolsAPI
    private let onSaved: @MainActor (AppointmentDetail) -> Void

    public init(appointment: Appointment, documentation: String, api: any TToolsAPI,
                onSaved: @escaping @MainActor (AppointmentDetail) -> Void = { _ in }) {
        self.appointment = appointment
        self.text = documentation
        self.base = documentation
        self.api = api
        self.onSaved = onSaved
    }

    public var isDirty: Bool { text != base }
    public var canSave: Bool { isDirty && phase != .saving }

    /// Returns true when saved.
    @discardableResult
    public func save() async -> Bool {
        guard canSave else { return false }
        phase = .saving
        do {
            // Never overwrites a text she has not seen: the API checks `base` is still stored.
            let detail = try await api.saveDocumentation(text, for: appointment.id, replacing: base)
            base = detail.documentation
            phase = .editing
            savedCount += 1
            onSaved(detail)
            return true
        } catch let conflict as DocumentationConflict {
            phase = .conflict(conflict.current)
        } catch let e as APIError {
            phase = .failed(e)
        } catch {
            phase = .failed(.server(status: 0))
        }
        return false
    }

    /// Conflict: keep both, theirs first, her draft below. She reviews and saves again.
    public func mergeConflict() {
        guard case .conflict(let theirs) = phase else { return }
        let draft = text.hasPrefix(base) && !base.isEmpty ? String(text.dropFirst(base.count)).trimmingCharacters(in: .whitespacesAndNewlines) : text
        text = theirs.isEmpty ? draft : theirs + "\n\n" + draft
        base = theirs
        phase = .editing
    }

    /// Conflict: drop her draft and take what TTools has.
    public func takeTheirs() {
        guard case .conflict(let theirs) = phase else { return }
        text = theirs
        base = theirs
        phase = .editing
    }

    public func dismissError() {
        if case .failed = phase { phase = .editing }
    }
}
