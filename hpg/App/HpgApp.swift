import SwiftUI

@main
struct HpgApp: App {
    @State private var monitor = Monitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(monitor)
                .onChange(of: scenePhase) { _, p in monitor.scenePhaseChanged(p) }
        }
    }
}

struct RootView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        Group {
            switch monitor.phase {
            case .loggedOut, .connecting: LoginView()
            case .connected, .lost: MainView()
            }
        }
        #if DEBUG
        // `-demo` (and `-tab 1`) let simulator runs open straight onto demo data.
        .task {
            if CommandLine.arguments.contains("-demo") { monitor.showDemo() }
            // `-pushwait` shows the "approve the Duo push" screen (layout check only).
            if CommandLine.arguments.contains("-pushwait") { monitor.pushSent = true; monitor.phase = .connecting }
            // `-duo` shows a sample of the Duo prompt (layout check only; answering does nothing).
            if CommandLine.arguments.contains("-duo") {
                monitor.challenge = AuthChallenge(name: "", instruction: "", prompts: [.init(text: """
                    Duo two-factor login for demo

                    Enter a passcode or select one of the following options:

                     1. Duo Push to XXX-XXX-1234
                     2. Phone call to XXX-XXX-1234
                     3. SMS passcodes to XXX-XXX-1234

                    Passcode or option (1-3):\u{20}
                    """, echo: true)])
            }
        }
        #endif
        .sheet(item: Binding(get: { monitor.challenge }, set: { if $0 == nil, monitor.challenge != nil { monitor.answer(nil) } })) { c in
            AuthPromptView(challenge: c)
        }
    }
}

struct MainView: View {
    @Environment(Monitor.self) private var monitor
    @State private var showSettings = false
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $tab.onChange { _ in Haptics.select() }) {
            Tab("Jobs", systemImage: "list.bullet.rectangle", value: 0) {
                NavigationStack { JobsView().toolbar { toolbar(allocations: false) } }
            }
            Tab("Allocations", systemImage: "gauge.with.dots.needle.50percent", value: 1) {
                NavigationStack { AllocationsView().toolbar { toolbar(allocations: true) } }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if case .lost(let why) = monitor.phase { LostBanner(reason: why) }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.regularMaterial, in: .capsule)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .padding(.top, 58).padding(.horizontal, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toast)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// Turns "Stay connected in background" (location) on or off, and says what that means.
    private func toggleBackground() {
        Haptics.select()
        monitor.stayConnected.toggle()
        let on = monitor.stayConnected
        if on && monitor.keeper.denied {
            show("Location is off for hpg in iOS Settings, so background mode can't work.")
        } else {
            show(on ? "Background on: hpg stays connected when you leave it (uses location)."
                    : "Background off: no location. hpg disconnects soon after you leave it.")
        }
    }

    private func show(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { toast = nil }
        }
    }

    @ToolbarContentBuilder private func toolbar(allocations: Bool) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { StatusBadge(allocations: allocations) }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: toggleBackground) {
                Image(systemName: monitor.stayConnected ? "location.fill" : "location.slash")
                    .foregroundStyle(monitor.stayConnected ? Color.blue : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(monitor.stayConnected ? "Background mode on" : "Background mode off")
            .accessibilityHint("Turns location-based background mode on or off")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { Haptics.tap(); showSettings = true } label: { Image(systemName: "gearshape") }
        }
    }
}

/// Green dot + "updated 3s ago", ticking every second.
struct StatusBadge: View {
    @Environment(Monitor.self) private var monitor
    var allocations = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label(ctx.date)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .fixedSize()
            .padding(.horizontal, 6)
        }
    }

    private var color: Color {
        switch monitor.phase {
        case .connected: return monitor.demo ? .blue : .green
        case .lost: return .red
        default: return .orange
        }
    }

    private func label(_ now: Date) -> String {
        if monitor.demo { return "demo data" }
        if case .lost = monitor.phase { return "disconnected" }
        guard let t = allocations ? monitor.allocationsUpdated : monitor.jobsUpdated else { return "loading…" }
        return "updated \(max(0, Int(now.timeIntervalSince(t))))s ago"
    }
}

struct LostBanner: View {
    @Environment(Monitor.self) private var monitor
    let reason: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "bolt.horizontal.circle.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection lost").font(.subheadline.weight(.semibold))
                Text(reason).font(.caption).lineLimit(2)
            }
            Spacer()
            Button("Log in") { Haptics.tap(); monitor.disconnect() }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.red)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.red.gradient)
    }
}
