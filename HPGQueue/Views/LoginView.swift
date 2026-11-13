import SwiftUI

struct LoginView: View {
    @Environment(Monitor.self) private var monitor
    @State private var password = ""
    @FocusState private var focus: Field?
    private enum Field { case user, password }

    var body: some View {
        @Bindable var m = monitor
        let connecting = monitor.phase == .connecting
        NavigationStack {
            if connecting {
                LoginWaitingView()
            } else {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Image("Logo")
                            .resizable().scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(.rect(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                            .padding(.bottom, 6)
                        Text("hpg").font(.title2.bold())
                        Text("Your HiPerGator jobs and allocations, live.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Host", text: $m.host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Username", text: $m.user)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textContentType(.username).focused($focus, equals: .user)
                        .submitLabel(.next).onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password).focused($focus, equals: .password)
                        .submitLabel(.go).onSubmit(connect)
                    Toggle("Remember password", isOn: $m.rememberPassword.onChange { _ in Haptics.select() })
                } footer: {
                    Text("You'll approve a Duo prompt after your password. The password is kept in this iPhone's Keychain only.")
                }

                Section {
                    Button(action: connect) {
                        Text("Connect").bold().frame(maxWidth: .infinity)
                    }
                    .disabled(monitor.user.isEmpty || password.isEmpty)
                } footer: {
                    if let e = monitor.loginError {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button("Look around with demo data") { Haptics.tap(); monitor.showDemo() }
                        .frame(maxWidth: .infinity).font(.footnote)
                }
                .listRowBackground(Color.clear)
            }
            }
        }
        .animation(.default, value: connecting)
        .onAppear {
            if password.isEmpty, let saved = monitor.savedPassword { password = saved }
            if monitor.user.isEmpty { focus = .user }
        }
        .onChange(of: monitor.user) { _, _ in
            if let saved = monitor.savedPassword { password = saved }
        }
    }

    private func connect() {
        guard !monitor.user.isEmpty, !password.isEmpty else { return }
        Haptics.tap()
        focus = nil
        monitor.connect(password: password)
    }
}

/// Shown while logging in: "Connecting…", then "Check your phone" once the Duo push is sent.
struct LoginWaitingView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Group {
                if monitor.pushSent {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(.green)
                        .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                } else {
                    ProgressView().controlSize(.large)
                }
            }
            .frame(height: 90)

            Text(monitor.pushSent ? "Check your phone" : "Connecting…")
                .font(.title2.bold())
                .padding(.top, 20)
            Text(monitor.pushSent
                 ? "A Duo push is on its way. Approve it in Duo Mobile or from the notification, then come back here."
                 : "Signing in to \(monitor.host) as \(monitor.user).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 40)
            if monitor.pushSent && DuoLauncher.isInstalled {
                Button { Haptics.tap(); DuoLauncher.open() } label: {
                    Label("Open Duo Mobile", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.top, 28)
            }
            Spacer()
            Button(role: .cancel) { Haptics.tap(); monitor.disconnect() } label: {
                Text("Cancel").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .animation(.default, value: monitor.pushSent)
        .onChange(of: monitor.pushSent) { _, sent in
            // Give the push a moment to reach Duo, then switch over to approve it.
            guard sent, monitor.openDuoAutomatically else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                if monitor.phase == .connecting { DuoLauncher.open() }
            }
        }
    }
}

/// A keyboard-interactive prompt from the server: Duo (with one-tap option buttons), or a password retry.
struct AuthPromptView: View {
    @Environment(Monitor.self) private var monitor
    let challenge: AuthChallenge
    @State private var answers: [String]
    @FocusState private var focused: Int?

    init(challenge: AuthChallenge) {
        self.challenge = challenge
        _answers = State(initialValue: Array(repeating: "", count: challenge.prompts.count))
    }

    private var options: [(key: String, label: String)] { challenge.options }

    private var message: String {
        [challenge.name, challenge.instruction].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                if !message.isEmpty {
                    Section { Text(message).font(.callout.monospaced()) }
                }
                if challenge.prompts.count == 1, !options.isEmpty {
                    Section("Choose") {
                        ForEach(options, id: \.key) { o in
                            Button { Haptics.tap(); monitor.answer([o.key]) } label: {
                                Label(o.label, systemImage: icon(o.label))
                            }
                        }
                    }
                }
                ForEach(challenge.prompts.indices, id: \.self) { i in
                    let p = challenge.prompts[i]
                    Section {
                        if p.echo {
                            TextField("Answer", text: $answers[i])
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .keyboardType(options.isEmpty ? .default : .numberPad)
                                .focused($focused, equals: i)
                        } else {
                            SecureField("Answer", text: $answers[i]).focused($focused, equals: i)
                        }
                    } header: {
                        Text(promptTitle(p.text)).textCase(nil)
                    } footer: {
                        if !options.isEmpty { Text("Or type a Duo passcode.") }
                    }
                }
                Section {
                    Button("Submit") { Haptics.tap(); monitor.answer(answers) }
                        .frame(maxWidth: .infinity).bold()
                        .disabled(answers.contains(where: \.isEmpty))
                }
            }
            .navigationTitle(options.isEmpty ? "Login" : "Duo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { Haptics.tap(); monitor.answer(nil) } }
            }
            .onAppear {
                if options.isEmpty { focused = 0 }
                // Duo: put the keyboard away so the Push / Call buttons are in view.
                else { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    /// The last line of the prompt ("Passcode or option (1-3):"), since the options are shown as buttons.
    private func promptTitle(_ text: String) -> String {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return options.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : (lines.last ?? text)
    }

    private func icon(_ label: String) -> String {
        let l = label.lowercased()
        if l.contains("push") { return "iphone.radiowaves.left.and.right" }
        if l.contains("call") { return "phone" }
        if l.contains("sms") || l.contains("text") { return "message" }
        return "key"
    }
}
