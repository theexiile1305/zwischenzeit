import CalendarFeature
import DesignSystem
import DocumentationFeature
import Domain
import Observation
import SwiftUI

/// Loads one appointment for the detail screen. The documentation is the one thing it can write.
@MainActor @Observable
public final class AppointmentDetailModel {
    public let id: AppointmentID
    public private(set) var detail: AppointmentDetail?
    public private(set) var error: APIError?

    let api: any TToolsAPI
    public let reference: ReferenceData
    /// Whose calendar this is (the signed-in employee). Their own name is not repeated on the services.
    public let ownerID: EmployeeID?
    let now: () -> Date

    public init(id: AppointmentID, api: any TToolsAPI, reference: ReferenceData, ownerID: EmployeeID? = nil,
                now: @escaping () -> Date = { .now }) {
        self.id = id
        self.api = api
        self.reference = reference
        self.ownerID = ownerID
        self.now = now
    }

    public func load() async {
        do {
            detail = try await api.appointmentDetail(id)
            error = nil
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .server(status: 0)
        }
    }

    func editorModel(for detail: AppointmentDetail) -> DocumentationEditorModel {
        DocumentationEditorModel(appointment: detail.appointment, documentation: detail.documentation, api: api) { [weak self] in
            self?.detail = $0
        }
    }

    func treatmentName(_ a: Appointment) -> String {
        a.services.first.flatMap { reference.treatmentType($0.treatmentTypeID)?.name } ?? "Behandlung"
    }
}

/// Detail screen: one appointment with its services, prescription and documentation.
public struct AppointmentDetailView: View {
    @State private var model: AppointmentDetailModel
    @State private var editor: DocumentationEditorModel?
    /// Opens the editor once loaded (screenshots: `-route documentation`).
    private let startEditing: Bool

    public init(model: AppointmentDetailModel, startEditing: Bool = false) {
        _model = State(initialValue: model)
        self.startEditing = startEditing
    }

    public var body: some View {
        Group {
            if let detail = model.detail {
                content(detail)
            } else if let error = model.error {
                ContentUnavailableView {
                    Label("Termin nicht verfügbar", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                } actions: {
                    DSButton("Erneut laden") { Task { await model.load() } }
                }
            } else {
                ProgressView("Lädt …")
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            if model.detail == nil { await model.load() }
            if startEditing, editor == nil, let detail = model.detail { editor = model.editorModel(for: detail) }
        }
        .sheet(item: $editor) { editor in
            DocumentationEditor(model: editor, treatment: model.treatmentName(editor.appointment))
        }
        .refreshable { await model.load() }
    }

    private var title: String {
        guard let a = model.detail?.appointment else { return "" }
        return a.patient?.fullName ?? "Blockierte Zeit"
    }

    private func content(_ detail: AppointmentDetail) -> some View {
        let a = detail.appointment
        return List {
            Section {
                HeroHeader(appointment: a, reference: model.reference, now: model.now())
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if let n = a.sessionNumber, let m = a.sessionsTotal {
                Section("Rezept-Fortschritt") {
                    VStack(alignment: .leading, spacing: DS.Space.s8) {
                        HStack {
                            Text("Behandlung \(n) von \(m)").font(.headline).monospacedDigit()
                            Spacer()
                            if m > n { Text("noch \(m - n)").font(.subheadline).foregroundStyle(DS.Color.textMuted) }
                        }
                        DSProgressSegments(current: n, total: m,
                                           tint: a.isLastSession ? DS.Color.warning : DS.Color.accent)
                    }
                    .padding(.vertical, DS.Space.s4)
                    .accessibilityElement(children: .combine)
                    if a.isLastSession {
                        Label {
                            VStack(alignment: .leading, spacing: DS.Space.s2) {
                                Text("Letzte Behandlung dieses Rezepts").font(.subheadline.weight(.semibold))
                                Text("Folgeverordnung mit dem Patienten klären.").font(.footnote).foregroundStyle(DS.Color.textMuted)
                            }
                        } icon: {
                            Image(systemName: "flag.checkered").foregroundStyle(DS.Color.warning)
                        }
                    } else if a.isFirstSession {
                        Label {
                            VStack(alignment: .leading, spacing: DS.Space.s2) {
                                Text("Erste Behandlung").font(.subheadline.weight(.semibold))
                                Text("Befund und Anamnese einplanen.").font(.footnote).foregroundStyle(DS.Color.textMuted)
                            }
                        } icon: {
                            Image(systemName: "sparkles").foregroundStyle(DS.Color.accent)
                        }
                    }
                }
            }

            if a.kind == .blocker, let note = a.note {
                Section("Notiz") { Text(note) }
            }

            Section("Leistungen") {
                if a.services.isEmpty {
                    Text("Keine Leistung hinterlegt").foregroundStyle(DS.Color.textMuted)
                }
                ForEach(a.services) { ServiceRow(service: $0, reference: model.reference, ownerID: model.ownerID) }
            }

            if !detail.prescriptions.isEmpty {
                Section("Rezepte") {
                    PrescriptionPager(prescriptions: detail.prescriptions, patient: a.patient, linkedID: a.prescriptionID)
                        .listRowInsets(EdgeInsets(top: DS.Space.s12, leading: 0, bottom: DS.Space.s12, trailing: 0))
                }
            }

            if a.kind == .treatment {
                Section("Dokumentation") {
                    if detail.documentation.isEmpty {
                        Button { editor = model.editorModel(for: detail) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: DS.Space.s2) {
                                    Text("Dokumentieren").font(.body.weight(.semibold))
                                    Text("Noch nichts dokumentiert").font(.footnote).foregroundStyle(DS.Color.textMuted)
                                }
                            } icon: {
                                Image(systemName: "square.and.pencil").foregroundStyle(DS.Color.accent)
                            }
                            .padding(.vertical, DS.Space.s4)
                        }
                    } else {
                        Text(detail.documentation).textSelection(.enabled)
                        Button { editor = model.editorModel(for: detail) } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                    }
                }
            }
        }
    }
}

/// Time first, big: that is what she checks between two patients.
struct HeroHeader: View {
    let appointment: Appointment
    let reference: ReferenceData
    let now: Date

    var body: some View {
        let a = appointment
        let type = a.services.first.flatMap { reference.treatmentType($0.treatmentTypeID) }
        let style: TreatmentStyle = a.kind == .blocker ? .blocker : TreatmentStyle(type?.category ?? .other)
        let room = reference.room(a.services.first(where: { $0.roomID != nil })?.roomID)?.name
        let day = PracticeCalendar.relativeDayName(a.start, now: now).map { "\($0), \(PracticeCalendar.format(a.start, "dMMMM"))" }
            ?? PracticeCalendar.format(a.start, "EEEEdMMMMyyyy")

        VStack(alignment: .leading, spacing: DS.Space.s8) {
            HStack(spacing: DS.Space.s8) {
                Text(type?.name ?? (a.kind == .blocker ? "Blockierte Zeit" : "Behandlung"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style.foreground)
                    .padding(.horizontal, DS.Space.s8)
                    .padding(.vertical, DS.Space.s2)
                    .background(Capsule().fill(style.fill))
                    .overlay(Capsule().strokeBorder(style.edge, lineWidth: 1))
                    .lineLimit(1)
                if a.services.count > 1 { DSBadge("+\(a.services.count - 1)") }
                Spacer(minLength: 0)
                switch a.status {
                case .cancelled: DSBadge("Abgesagt", systemImage: "xmark", tone: .danger)
                case .arrived: DSBadge("Ist da", systemImage: "person.fill.checkmark", tone: .success)
                case .planned:
                    if a.start <= now && a.end > now { DSBadge("Läuft", systemImage: "play.fill", tone: .accent) }
                }
            }
            Text("\(PracticeCalendar.time(a.start))–\(PracticeCalendar.time(a.end))")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .strikethrough(a.status == .cancelled)
            Text(day).font(.headline).foregroundStyle(DS.Color.textMuted)
            HStack(spacing: DS.Space.s4) {
                DSBadge(Countdown.duration(minutes: a.durationMinutes), systemImage: "clock")
                if let room { DSBadge(room, systemImage: "door.left.hand.open") }
                if a.groupID != nil { DSBadge("Gruppe", systemImage: "person.3") }
                if a.seriesID != nil { DSBadge("Serie", systemImage: "infinity") }
            }
        }
        .foregroundStyle(DS.Color.text)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s8)
        .accessibilityElement(children: .combine)
    }
}

/// Full-width, paged prescription cards. The linked one is first (the API sorts it so).
struct PrescriptionPager: View {
    let prescriptions: [Prescription]
    let patient: Patient?
    let linkedID: PrescriptionID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: DS.Space.s8) {
                ForEach(Array(prescriptions.enumerated()), id: \.element.id) { i, rx in
                    PrescriptionCard(prescription: rx, patient: patient, index: i,
                                     count: prescriptions.count, isLinked: rx.id == linkedID)
                        .containerRelativeFrame(.horizontal) { width, _ in
                            prescriptions.count > 1 ? width - 48 : width - 32
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, DS.Space.s16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }
}

struct ServiceRow: View {
    let service: AppointmentService
    let reference: ReferenceData
    let ownerID: EmployeeID?

    var body: some View {
        let type = reference.treatmentType(service.treatmentTypeID)
        HStack(spacing: DS.Space.s12) {
            RoundedRectangle(cornerRadius: DS.Layout.edgeBarRadius)
                .fill(TreatmentStyle(type?.category ?? .other).edge)
                .frame(width: DS.Layout.edgeBarWidth)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(type?.name ?? "Unbekannte Leistung")
                // The owner's own name on every row says nothing; a colleague's does.
                let colleague = service.employeeID == ownerID ? nil : reference.employee(service.employeeID)?.displayName
                Text([reference.room(service.roomID)?.name, "\(service.durationMinutes) Min.", colleague]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(DS.Color.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PrescriptionCard: View {
    let prescription: Prescription
    let patient: Patient?
    let index: Int
    let count: Int
    let isLinked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack {
                Text("Rezept \(prescription.number)").font(.subheadline.weight(.semibold)).monospacedDigit()
                Spacer()
                DSStatusPill(pill)
            }
            if let patient { Text(patient.fullName).font(.footnote).foregroundStyle(DS.Color.textMuted) }
            Text("\(prescription.sessionsTotal) Einheiten verordnet").font(.footnote).foregroundStyle(DS.Color.textMuted)
            if isLinked {
                Label("Gehört zu diesem Termin", systemImage: "link").font(.caption).foregroundStyle(DS.Color.accent)
            }
        }
        .padding(DS.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(isLinked ? DS.Color.accent : DS.Color.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rezept \(prescription.number), \(statusText), \(index + 1) von \(count)")
    }

    private var pill: DSStatusPill.Status {
        switch prescription.status {
        case .open, .unknown: .open
        case .completed: .completed
        case .cancelled: .cancelled
        }
    }

    private var statusText: String {
        switch prescription.status {
        case .open, .unknown: "offen"
        case .completed: "abgeschlossen"
        case .cancelled: "storniert"
        }
    }
}
