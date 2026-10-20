import Domain
import Foundation
import MockAPI
import Testing
@testable import DocumentationFeature

private let now = PracticeCalendar.date(on: PracticeCalendar.calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!, hour: 9, minute: 0)

@MainActor
private func upcomingTreatment(_ api: MockTToolsAPI) async throws -> AppointmentDetail {
    let day = DateInterval(start: PracticeCalendar.startOfDay(now), duration: 86_400)
    let a = try await api.appointments(for: EmployeeID("e1"), in: day).first { $0.kind == .treatment && $0.start > now }!
    return try await api.appointmentDetail(a.id)
}

@MainActor @Suite struct DocumentationEditorModelTests {
    @Test func savesAndReportsTheFreshDetail() async throws {
        let api = MockTToolsAPI(now: now, latency: .zero)
        let detail = try await upcomingTreatment(api)
        var saved: AppointmentDetail?
        let model = DocumentationEditorModel(appointment: detail.appointment, documentation: detail.documentation, api: api) { saved = $0 }
        #expect(!model.canSave)
        model.text = "KG durchgeführt."
        #expect(await model.save())
        #expect(saved?.documentation == "KG durchgeführt.")
        #expect(!model.isDirty)
        #expect(model.savedCount == 1)
        #expect(try await api.appointmentDetail(detail.appointment.id).documentation == "KG durchgeführt.")
    }

    @Test func doesNotOverwriteAChangeMadeInTToolsMeanwhile() async throws {
        let api = MockTToolsAPI(now: now, latency: .zero)
        let detail = try await upcomingTreatment(api)
        let model = DocumentationEditorModel(appointment: detail.appointment, documentation: detail.documentation, api: api)
        _ = try await api.saveDocumentation("Von der Kollegin.", for: detail.appointment.id, replacing: detail.documentation)
        model.text = "Mein Text."
        #expect(await model.save() == false)
        #expect(model.phase == .conflict("Von der Kollegin."))
        #expect(try await api.appointmentDetail(detail.appointment.id).documentation == "Von der Kollegin.")

        model.mergeConflict()
        #expect(model.text == "Von der Kollegin.\n\nMein Text.")
        #expect(await model.save())
    }

    @Test func takeTheirsDropsTheDraft() async throws {
        let api = MockTToolsAPI(now: now, latency: .zero)
        let detail = try await upcomingTreatment(api)
        let model = DocumentationEditorModel(appointment: detail.appointment, documentation: detail.documentation, api: api)
        _ = try await api.saveDocumentation("Neu.", for: detail.appointment.id, replacing: detail.documentation)
        model.text = "Entwurf"
        await model.save()
        model.takeTheirs()
        #expect(model.text == "Neu.")
        #expect(!model.isDirty)
    }

    @Test func offlineKeepsTheDraft() async throws {
        let api = MockTToolsAPI(now: now, latency: .zero)
        let detail = try await upcomingTreatment(api)
        let model = DocumentationEditorModel(appointment: detail.appointment, documentation: detail.documentation, api: api)
        model.text = "Entwurf"
        await api.setFailure(.offline)
        #expect(await model.save() == false)
        #expect(model.phase == .failed(.offline))
        #expect(model.text == "Entwurf")
    }
}

@MainActor @Suite struct SnippetStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "snippets-\(UUID().uuidString).json")
    }

    @Test func startsWithDefaultsAndPersistsChanges() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SnippetStore(fileURL: url)
        #expect(store.snippets == TextSnippet.defaults)
        store.upsert(TextSnippet(title: "Eigener", body: "Eigener Text."))
        store.delete(at: [0])
        #expect(store.saveError == nil)
        #expect(SnippetStore(fileURL: url).snippets == store.snippets)
        #expect(store.snippets.last?.title == "Eigener")
    }

    @Test func movesLikeAList() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SnippetStore(fileURL: url)
        let titles = store.snippets.map(\.title)
        store.move(from: [0], to: 3)
        #expect(store.snippets.map(\.title) == [titles[1], titles[2], titles[0]] + titles[3...])
        store.resetToDefaults()
        #expect(store.snippets == TextSnippet.defaults)
    }
}
