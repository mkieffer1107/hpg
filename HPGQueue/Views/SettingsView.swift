import SwiftUI

struct SettingsView: View {
    @Environment(Monitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var forgotKey = false

    var body: some View {
        @Bindable var m = monitor
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Host", value: monitor.demo ? "demo" : monitor.host)
                    LabeledContent("User", value: monitor.demo ? "demo" : monitor.user)
                    Button(monitor.demo ? "Leave demo" : "Disconnect", role: .destructive) {
                        Haptics.tap()
                        monitor.disconnect(); dismiss()
                    }
                }

                Section {
                    Toggle("Stay connected in background", isOn: $m.stayConnected.onChange { _ in Haptics.select() })
                        .onChange(of: monitor.stayConnected) { _, on in if on { monitor.keeper.requestPermission() } }
                    if monitor.stayConnected && monitor.keeper.denied {
                        Label("Location access is off, so iOS will pause the app soon after you leave it. Turn it on in Settings › hpg › Location (While Using).",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Keeps the SSH session open when you go to the Home Screen, so you don't have to log in and approve Duo again. iOS only lets apps stay awake in the background for a few reasons, so this uses the coarsest location updates (nothing is stored or sent), and you'll see the blue location indicator. Swiping the app away still closes the connection.")
                }

                Section("Refresh") {
                    Stepper("Jobs every \(Int(monitor.jobsInterval))s", value: $m.jobsInterval.onChange { _ in Haptics.select() }, in: 2...60, step: 1)
                    Stepper("Allocations every \(Int(monitor.allocationsInterval))s", value: $m.allocationsInterval.onChange { _ in Haptics.select() }, in: 10...300, step: 10)
                }

                Section {
                    Toggle("Open Duo Mobile automatically", isOn: $m.openDuoAutomatically.onChange { _ in Haptics.select() })
                } footer: {
                    Text("When you log in, hpg sends the Duo push and switches to Duo Mobile so you can approve it. Come back to hpg afterwards.")
                }

                Section {
                    Button("Forget saved host key") { Haptics.tap(); monitor.forgetHostKey(); forgotKey = true }
                        .disabled(forgotKey)
                } footer: {
                    Text("The server's key is remembered on first login and checked every time after. Only reset it if HiPerGator announced a key change.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { Haptics.tap(); dismiss() } } }
        }
    }
}
