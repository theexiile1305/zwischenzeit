import DesignSystem
import Domain
import SwiftUI

#if !os(watchOS) // TextEditor does not exist on watchOS; SettingsFeature also builds for the watch.

/// Einstellungen → Textbausteine: add, edit, reorder, delete, reset.
public struct SnippetManagerView: View {
    @Bindable var store: SnippetStore
    @State private var editing: TextSnippet?
    @State private var confirmReset = false

    public init(store: SnippetStore = .shared) {
        self.store = store
    }

    public var body: some View {
        List {
            Section {
                ForEach(store.snippets) { snippet in
                    Button { editing = snippet } label: {
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            Text(snippet.title).font(.body.weight(.semibold)).foregroundStyle(DS.Color.text)
                            Text(snippet.body).font(.subheadline).foregroundStyle(DS.Color.textMuted).lineLimit(2)
                        }
                        .padding(.vertical, DS.Space.s2)
                    }
                }
                .onDelete(perform: store.delete)
                .onMove(perform: store.move)
                Button { editing = TextSnippet(title: "", body: "") } label: {
                    Label("Neuer Baustein", systemImage: "plus.circle.fill")
                }
            } footer: {
                if store.saveError != nil {
                    Text("Änderungen konnten nicht gespeichert werden und gehen beim Beenden der App verloren.")
                        .foregroundStyle(DS.Color.danger)
                }
                Text("Erscheinen beim Dokumentieren als Leiste über der Tastatur. Ein Tipp fügt den Text an der Schreibmarke ein.")
            }

            Section {
                Button("Standardbausteine wiederherstellen", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Textbausteine")
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
        .sheet(item: $editing) { snippet in
            NavigationStack {
                SnippetEditView(snippet: snippet) { store.upsert($0) }
            }
        }
        .confirmationDialog("Eigene Textbausteine durch die Standard-Textbausteine ersetzen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Wiederherstellen", role: .destructive) { store.resetToDefaults() }
        }
    }
}

private struct SnippetEditView: View {
    @State var snippet: TextSnippet
    let onSave: (TextSnippet) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !snippet.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !snippet.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Kurzname") {
                TextField("z. B. Wie geplant", text: $snippet.title)
            }
            Section {
                TextEditor(text: $snippet.body)
                    .frame(minHeight: 120)
            } header: {
                Text("Text")
            } footer: {
                Text("Textbausteine werden nur auf diesem Gerät gespeichert. Bitte keine Patientennamen eintragen.")
            }
            Section("Platzhalter") {
                ForEach(TextSnippet.placeholders, id: \.token) { p in
                    Button {
                        snippet.body = SnippetInsertion.insert(p.token, into: snippet.body, replacing: nil).text
                    } label: {
                        LabeledContent { Text(p.help).font(.footnote) } label: {
                            Text(p.token).font(.body.monospaced())
                        }
                    }
                }
            }
        }
        .navigationTitle(snippet.title.isEmpty ? "Neuer Baustein" : snippet.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { onSave(snippet); dismiss() }.disabled(!isValid)
            }
        }
    }
}
#endif
