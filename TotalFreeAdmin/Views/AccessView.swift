import SwiftUI

/// Sign in / Join. Presented as a sheet from any place that needs an account.
struct AuthView: View {
    enum Mode: String, CaseIterable { case signIn = "Sign in", join = "Join" }

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?
    private enum Field { case name, email, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(OAuthProvider.allCases) { provider in
                        Button {
                            socialSignIn(provider)
                        } label: {
                            HStack {
                                Image(systemName: provider.systemImage)
                                    .frame(width: 22)
                                Text(provider.label)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(appState.isBusy)
                    }
                } footer: {
                    Text("Use the same account providers as the web app.")
                }

                Section {
                    if mode == .join {
                        TextField("Your name", text: $name)
                            .textContentType(.name)
                            .focused($focused, equals: .name)
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                    SecureField("Password", text: $password)
                        .textContentType(mode == .join ? .newPassword : .password)
                        .focused($focused, equals: .password)
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if appState.isBusy { ProgressView() }
                            else { Text(mode == .signIn ? "Sign in" : "Create account").bold() }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit || appState.isBusy)
                } footer: {
                    Text(mode == .join
                         ? "Browsing is always free. An account lets you post, request items, and message neighbours. You may need to confirm your email."
                         : "Welcome back.")
                }
            }
            .navigationTitle(mode == .signIn ? "Sign in" : "Join Total Free")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: appState.isAuthed) { _, authed in
                if authed { dismiss() }
            }
        }
    }

    private func socialSignIn(_ provider: OAuthProvider) {
        focused = nil
        Task { await appState.signInWithOAuth(provider) }
    }

    private var canSubmit: Bool {
        let validEmail = email.contains("@") && email.contains(".")
        let validPassword = password.count >= 6
        let validName = mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty
        return validEmail && validPassword && validName
    }

    private func submit() {
        focused = nil
        Task {
            switch mode {
            case .signIn:
                await appState.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            case .join:
                await appState.signUp(
                    name: name.trimmingCharacters(in: .whitespaces),
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            }
        }
    }
}

/// Friendly call-to-action shown on member-only screens when signed out.
struct SignInPrompt: View {
    let title: String
    let message: String
    var systemImage: String = "person.crop.circle.badge.plus"
    @State private var showAuth = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text(title).font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showAuth = true
            } label: {
                Text("Sign in or join").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 420)
        .sheet(isPresented: $showAuth) { AuthView() }
    }
}
