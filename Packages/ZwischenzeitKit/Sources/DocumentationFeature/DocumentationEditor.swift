import DesignSystem
import Domain
import SwiftUI

#if !os(watchOS) // TextEditor does not exist on watchOS; SettingsFeature also builds for the watch.

/// Full-screen sheet for one treatment's documentation: who and what at the top, the text,
/// and her Textbausteine as a chip bar right above the keyboard.
public struct DocumentationEditor: View {
    @State private var model: DocumentationEditorModel
    let treatment: String
    @Bindable var store: SnippetStore

    @State private var pendingInsert: String?
    @State private var insertCount = 0
    @State private var confirmDiscard = false
    @State private var showManager = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(model: DocumentationEditorModel, treatment: String, store: SnippetStore = .shared) {
        _model = State(initialValue: model)
        self.treatment = treatment
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ContextHeader(appointment: model.appointment, treatment: treatment)
                Divider()
                phaseBanner
                ZStack(alignment: .topLeading) {
                    DraftEditor(text: $model.text, pendingInsert: $pendingInsert, isFocused: $isFocused)
                    if model.text.isEmpty {
                        Text("Was wurde gemacht, wie wurde es vertragen?")
                            .foregroundStyle(DS.Color.textMuted)
                            .padding(.top, DS.Space.s8)
                            .padding(.leading, DS.Space.s4 + 1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .font(.body)
                .padding(.horizontal, DS.Space.s12)
                .padding(.top, DS.Space.s4)
                .disabled(model.phase == .saving)
            }
            .background(DS.Color.bg)
            .safeAreaInset(edge: .bottom, spacing: 0) { snippetBar }
            .navigationTitle("Dokumentation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .interactiveDismissDisabled(model.isDirty)
            .confirmationDialog("Änderungen verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) { dismiss() }
                Button("Weiter schreiben", role: .cancel) {}
            } message: {
                Text("Der Text ist noch nicht gespeichert.")
            }
            .sheet(isPresented: $showManager) {
                NavigationStack {
                    SnippetManagerView(store: store)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showManager = false } }
                        }
                }
            }
            .sensoryFeedback(.success, trigger: model.savedCount)
            .sensoryFeedback(.selection, trigger: insertCount)
            .sensoryFeedback(.error, trigger: model.phase) { _, new in
                if case .failed = new { return true } else { return false }
            }
            .onAppear { isFocused = true }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Abbrechen") { model.isDirty ? (confirmDiscard = true) : dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.phase == .saving {
                ProgressView()
            } else {
                Button("Speichern") {
                    Task { if await model.save() { dismiss() } }
                }
                .fontWeight(.semibold)
                .disabled(!model.canSave)
            }
        }
    }

    // MARK: Banners

    @ViewBuilder private var phaseBanner: some View {
        switch model.phase {
        case .failed(let error):
            Button { model.dismissError() } label: {
                DSBanner(LocalizedStringKey(error.message + " Der Text bleibt erhalten."), kind: error == .offline ? .offline : .error)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Zum Schließen tippen")
            .padding([.horizontal, .top], DS.Space.s12)
            .onAppear { AccessibilityNotification.Announcement(error.message).post() }
        case .conflict(let theirs):
            ConflictBanner(theirs: theirs, onKeepBoth: model.mergeConflict, onTakeTheirs: model.takeTheirs)
                .padding([.horizontal, .top], DS.Space.s12)
        case .editing, .saving:
            EmptyView()
        }
    }

    // MARK: Snippets

    private var snippetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s8) {
                ForEach(store.snippets) { snippet in
                    let body = snippet.expanded(for: model.appointment)
                    Button {
                        pendingInsert = body
                        insertCount += 1
                    } label: {
                        Text(snippet.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, DS.Space.s12)
                            .padding(.vertical, DS.Space.s8)
                            .foregroundStyle(DS.Color.accent)
                            .background(Capsule().fill(DS.Color.accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { pendingInsert = body; insertCount += 1 } label: { Label("Einfügen", systemImage: "text.insert") }
                    } preview: {
                        Text(body).padding(DS.Space.s16).frame(maxWidth: 320, alignment: .leading)
                    }
                    .accessibilityLabel("Baustein \(snippet.title)")
                    .accessibilityHint("Fügt ein: \(body)")
                }
                Button { showManager = true } label: {
                    Label("Textbausteine", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, DS.Space.s12)
                        .padding(.vertical, DS.Space.s8)
                        .foregroundStyle(DS.Color.textMuted)
                        .overlay(Capsule().strokeBorder(DS.Color.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Textbausteine bearbeiten")
            }
            .padding(.horizontal, DS.Space.s16)
            .padding(.vertical, DS.Space.s8)
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .disabled(model.phase == .saving)
    }
}

/// Time, patient, treatment, n/m: enough to be sure it is the right person without scrolling.
private struct ContextHeader: View {
    let appointment: Appointment
    let treatment: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s12) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(appointment.patient?.fullName ?? "Ohne Patient")
                    .font(.headline)
                    .lineLimit(1)
                Text("\(PracticeCalendar.format(appointment.start, "EEEdMMM")) · \(PracticeCalendar.time(appointment.start))–\(PracticeCalendar.time(appointment.end)) · \(treatment)")
                    .font(.subheadline)
                    .foregroundStyle(DS.Color.textMuted)
                    .lineLimit(2)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if let session = appointment.sessionLabel {
                DSBadge(session, tone: appointment.isLastSession ? .warning : .neutral)
            }
        }
        .padding(.horizontal, DS.Space.s16)
        .padding(.vertical, DS.Space.s12)
        .background(DS.Color.surface)
        .accessibilityElement(children: .combine)
    }
}

private struct ConflictBanner: View {
    let theirs: String
    let onKeepBoth: () -> Void
    let onTakeTheirs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Label("In TTools wurde die Dokumentation inzwischen geändert.", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote.weight(.semibold))
            if !theirs.isEmpty {
                Text(theirs)
                    .font(.footnote)
                    .foregroundStyle(DS.Color.textMuted)
                    .lineLimit(3)
            }
            HStack(spacing: DS.Space.s8) {
                DSButton("Beide behalten", action: onKeepBoth)
                DSButton("TTools-Stand nehmen", variant: .plain, action: onTakeTheirs)
            }
        }
        .padding(DS.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.warning.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.warning, lineWidth: 1))
    }
}

/// TextEditor that inserts snippets at the cursor (iOS 18+) or at the end (iOS 17).
private struct DraftEditor: View {
    @Binding var text: String
    @Binding var pendingInsert: String?
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        if #available(iOS 18, macOS 15, *) {
            CursorEditor(text: $text, pendingInsert: $pendingInsert, isFocused: isFocused)
        } else {
            TextEditor(text: $text)
                .focused(isFocused)
                .scrollContentBackground(.hidden)
                .onChange(of: pendingInsert) {
                    guard let snippet = pendingInsert else { return }
                    text = SnippetInsertion.insert(snippet, into: text, replacing: nil).text
                    pendingInsert = nil
                }
        }
    }
}

@available(iOS 18, macOS 15, *)
private struct CursorEditor: View {
    @Binding var text: String
    @Binding var pendingInsert: String?
    var isFocused: FocusState<Bool>.Binding
    @State private var selection: TextSelection?

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .focused(isFocused)
            .scrollContentBackground(.hidden)
            .onChange(of: pendingInsert) {
                guard let snippet = pendingInsert else { return }
                pendingInsert = nil
                var range: Range<Int>?
                if case .selection(let r) = selection?.indices,
                   r.lowerBound >= text.startIndex, r.upperBound <= text.endIndex {
                    range = text.distance(from: text.startIndex, to: r.lowerBound)..<text.distance(from: text.startIndex, to: r.upperBound)
                }
                let result = SnippetInsertion.insert(snippet, into: text, replacing: range)
                text = result.text
                selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: result.cursor))
                isFocused.wrappedValue = true
            }
    }
}
#endif
