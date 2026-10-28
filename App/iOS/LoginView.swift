import DesignSystem
import SwiftUI

struct LoginView: View {
    let model: AppModel
    // Einrichtung and Benutzer are remembered like in the web app; the password never is.
    @AppStorage("login.practice") private var practice = ""
    // Empty initial values, not secrets (mobsfscan's hardcoded-secret rule matches on the names).
    @AppStorage("login.username") private var username = "" // mobsf-ignore: ios_hardcoded_secret
    @State private var password = "" // mobsf-ignore: ios_hardcoded_secret
    @State private var code = ""
    @State private var isSigningIn = false
    @FocusState private var focus: Field?

    enum Field { case practice, username, password, code }

    var body: some View {
        NavigationStack {
            Form {
                if model.needsMFA { mfaStep } else { passwordStep }
            }
            .navigationTitle("Zwischenzeit")
            .onAppear { focus = practice.isEmpty ? .practice : username.isEmpty ? .username : .password }
            .onChange(of: model.needsMFA) { _, needs in
                code = ""
                if needs { focus = .code } else { password = "" }
            }
        }
    }

    @ViewBuilder private var passwordStep: some View {
        Section {
            TextField("Einrichtung", text: $practice)
                .textContentType(.organizationName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($focus, equals: .practice)
                .submitLabel(.next)
                .onSubmit { focus = .username }
            TextField("Benutzer", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($focus, equals: .username)
                .submitLabel(.next)
                .onSubmit { focus = .password }
            SecureField("Passwort", text: $password)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit(signIn)
        } footer: {
            footer("Mit den Zugangsdaten der Praxissoftware anmelden.")
        }
        Section {
            DSButton("Anmelden", isLoading: isSigningIn, action: signIn)
                .frame(maxWidth: .infinity)
                .disabled(practice.isEmpty || username.isEmpty || password.isEmpty)
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private var mfaStep: some View {
        Section {
            TextField("Code", text: $code)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled(true)
                .keyboardType(.numberPad)
                .focused($focus, equals: .code)
                .onChange(of: code) { _, new in
                    code = String(new.filter(\.isNumber).prefix(6))
                    if code.count == 6 { submitCode() }
                }
        } header: {
            Text("Zwei-Faktor-Anmeldung")
        } footer: {
            footer("Den 6-stelligen Code aus der Authenticator-App eingeben.")
        }
        Section {
            DSButton("Bestätigen", isLoading: isSigningIn, action: submitCode)
                .frame(maxWidth: .infinity)
                .disabled(code.count != 6)
                .listRowBackground(Color.clear)
            Button("Abbrechen", role: .cancel) { model.cancelMFA() }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private func footer(_ hint: String) -> some View {
        if let error = model.signInError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Color.danger)
                .onAppear { AccessibilityNotification.Announcement(error).post() }
        } else {
            Text(hint)
        }
    }

    private func signIn() {
        let practice = practice.trimmingCharacters(in: .whitespaces), username = username.trimmingCharacters(in: .whitespaces)
        guard !practice.isEmpty, !username.isEmpty, !password.isEmpty, !isSigningIn else { return }
        isSigningIn = true
        Task {
            await model.signIn(practice: practice, username: username, password: password)
            isSigningIn = false
        }
    }

    private func submitCode() {
        guard code.count == 6, !isSigningIn else { return }
        isSigningIn = true
        Task {
            await model.submitMFA(code: code)
            isSigningIn = false
        }
    }
}
