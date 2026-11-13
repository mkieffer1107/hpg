import SwiftUI

struct LoginView: View {
    @Environment(Monitor.self) private var monitor
    @State private var password = ""
    @FocusState private var focus: Field?
    @State private var showLocationIntro = false
    @State private var connectAfterPermission = false
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
        .sheet(isPresented: $showLocationIntro) {
            LocationIntroView {
                // Continue: show iOS's prompt, and log in once it's answered.
                showLocationIntro = false
                connectAfterPermission = true
                monitor.keeper.requestPermission()
            } notNow: {
                showLocationIntro = false
                monitor.stayConnected = false
                startLogin()
            }
        }
        .onChange(of: monitor.keeper.status) { _, status in
            guard connectAfterPermission, status != .notDetermined else { return }
            connectAfterPermission = false
            startLogin()
        }
        #if DEBUG
        .task {
            // `-locationintro` previews the location explainer, as if Connect had just been tapped.
            if CommandLine.arguments.contains("-locationintro") {
                try? await Task.sleep(for: .milliseconds(300))
                focus = nil
                showLocationIntro = true
            }
        }
        #endif
        .onChange(of: monitor.user) { _, _ in
            if let saved = monitor.savedPassword { password = saved }
        }
    }

    private func connect() {
        guard !monitor.user.isEmpty, !password.isEmpty else { return }
        Haptics.tap()
        focus = nil
        // First time with "Stay connected" on: explain the location prompt before iOS shows it.
        if monitor.stayConnected && monitor.keeper.undecided {
            showLocationIntro = true
        } else {
            startLogin()
        }
    }

    private func startLogin() { monitor.connect(password: password) }
}

/// Shown once, before iOS's location prompt: why hpg asks, and which option to pick.
struct LocationIntroView: View {
    let `continue`: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.blue.gradient, in: .rect(cornerRadius: 18, style: .continuous))
                        Text("Stay connected in the background")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)

                    IntroRow(icon: "moon.zzz.fill", tint: .indigo,
                             title: "iOS pauses apps you leave",
                             text: "Soon after you switch away, iOS freezes hpg and the connection drops, so you'd need your password and Duo again.")
                    IntroRow(icon: "location.fill", tint: .blue,
                             title: "Location keeps hpg running",
                             text: "It's one of the few things iOS lets keep an app awake. hpg uses the coarsest setting (about 3 km) and ignores the result.")
                    IntroRow(icon: "lock.shield.fill", tint: .green,
                             title: "Nothing is stored or sent",
                             text: "Your location never leaves the phone. A blue pill shows in the status bar while it's on.")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("On the next screen, choose")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Allow While Using App")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                            .overlay(Capsule().strokeBorder(Color.blue, lineWidth: 2))
                        Text("Allow Once works too, but iOS will ask again every time you open hpg.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 24)
            }

            VStack(spacing: 10) {
                Button { Haptics.tap(); `continue`() } label: {
                    Text("Continue").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button { Haptics.tap(); notNow() } label: {
                    Text("Not now").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                Text("Not now logs in without background mode. You can turn it on later in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
        .onAppear { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }
}

private struct IntroRow: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
