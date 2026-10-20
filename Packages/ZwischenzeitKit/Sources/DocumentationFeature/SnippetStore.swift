import Domain
import Foundation
import Observation

/// Her Textbausteine, as JSON in Application Support. Generic text only, no patient data,
/// so this is not the appointment persistence the data-handling rules forbid.
@MainActor @Observable
public final class SnippetStore {
    public static let shared = SnippetStore(fileURL: SnippetStore.defaultURL)

    public private(set) var snippets: [TextSnippet]
    /// Set when the last write failed; the list keeps working from memory.
    public private(set) var saveError: String?
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        snippets = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([TextSnippet].self, from: $0) }
            ?? TextSnippet.defaults
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "textbausteine.json")
    }

    /// Inserts or replaces by id.
    public func upsert(_ snippet: TextSnippet) {
        if let i = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[i] = snippet
        } else {
            snippets.append(snippet)
        }
        save()
    }

    public func delete(at offsets: IndexSet) {
        for i in offsets.sorted(by: >) { snippets.remove(at: i) }
        save()
    }

    public func move(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { snippets[$0] }
        for i in source.sorted(by: >) { snippets.remove(at: i) }
        let target = destination - source.filter { $0 < destination }.count
        snippets.insert(contentsOf: moving, at: target)
        save()
    }

    public func resetToDefaults() {
        snippets = TextSnippet.defaults
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            let options: Data.WritingOptions = [.atomic, .completeFileProtection]
            #else
            let options: Data.WritingOptions = [.atomic]
            #endif
            try JSONEncoder().encode(snippets).write(to: fileURL, options: options)
            saveError = nil
        } catch {
            // The next change tries again.
            saveError = String(describing: type(of: error))
        }
    }
}
