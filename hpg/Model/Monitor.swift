import Foundation
import Observation
import SwiftUI

/// Owns the SSH session: login (password + Duo), polling squeue and the allocation report,
/// and keeping the session open while the app is in the background.
@MainActor @Observable
final class Monitor {
    enum Phase: Equatable { case loggedOut, connecting, connected, lost(String) }

    var phase: Phase = .loggedOut { didSet { updateKeeper() } }
    var loginError: String?
    var challenge: AuthChallenge?
    /// Set once the app has picked "Duo Push" for you; the login screen then says to approve it.
    var pushSent = false
    var jobs: JobsSnapshot?
    var allocations: AllocationsSnapshot?
    var jobsUpdated: Date?
    var allocationsUpdated: Date?
    var refreshError: String?
    var demo = false

    // Settings, persisted in UserDefaults.
    var host = UserDefaults.standard.string(forKey: "host") ?? "hpg.rc.ufl.edu" { didSet { save() } }
    var user = UserDefaults.standard.string(forKey: "user") ?? "" { didSet { save() } }
    var rememberPassword = UserDefaults.standard.object(forKey: "rememberPassword") as? Bool ?? true { didSet { save() } }
    var stayConnected = UserDefaults.standard.object(forKey: "stayConnected") as? Bool ?? true { didSet { save(); updateKeeper() } }
    var openDuoAutomatically = UserDefaults.standard.object(forKey: "openDuoAutomatically") as? Bool ?? true { didSet { save() } }
    var jobsInterval = UserDefaults.standard.object(forKey: "jobsInterval") as? Double ?? 15 { didSet { save() } }
    var allocationsInterval = UserDefaults.standard.object(forKey: "allocationsInterval") as? Double ?? 30 { didSet { save() } }

    let keeper = BackgroundKeeper()
    private let client = SSHClient()
    private var loop: Task<Void, Never>?
    private var inBackground = false
    private var answerBox: ((([String]?) -> Void))?

    var savedPassword: String? { Keychain.password(for: "\(user)@\(host)") }

    private func save() {
        let d = UserDefaults.standard
        d.set(host, forKey: "host"); d.set(user, forKey: "user")
        d.set(rememberPassword, forKey: "rememberPassword"); d.set(stayConnected, forKey: "stayConnected")
        d.set(openDuoAutomatically, forKey: "openDuoAutomatically")
        d.set(jobsInterval, forKey: "jobsInterval"); d.set(allocationsInterval, forKey: "allocationsInterval")
    }

    /// Keep the app alive in the background while logging in (Duo may send you to the Duo app)
    /// and, if the setting is on, while connected.
    private func updateKeeper() {
        keeper.setWanted(stayConnected && !demo && (phase == .connecting || phase == .connected))
    }

    private var fingerprintKey: String { "hostkey.\(host)" }

    func forgetHostKey() { UserDefaults.standard.removeObject(forKey: fingerprintKey) }

    // MARK: - login

    func connect(password: String) {
        guard phase != .connecting else { return }
        loginError = nil
        pushSent = false
        phase = .connecting
        demo = false
        let account = "\(user)@\(host)"
        Keychain.setPassword(rememberPassword ? password : nil, for: account)

        let passwordUsed = Flag(), pushUsed = Flag()
        let known = UserDefaults.standard.string(forKey: fingerprintKey)
        Task {
            do {
                let fp = try await client.connect(host: host, user: user, knownFingerprint: known) { challenge in
                    // Answer the first password prompt ourselves; anything else (Duo, a retry) goes to the UI.
                    if !passwordUsed.value, challenge.prompts.count == 1, !challenge.prompts[0].echo,
                       challenge.prompts[0].text.lowercased().contains("password") {
                        passwordUsed.value = true
                        return [password]
                    }
                    // Duo's menu: send the push ourselves (like typing 1 in the terminal). Only once, so a
                    // denied or timed-out push falls back to the full menu instead of looping.
                    if !pushUsed.value, let push = challenge.pushOption {
                        pushUsed.value = true
                        Task { @MainActor in self.pushSent = true }
                        return [push]
                    }
                    return self.askUser(challenge)
                }
                UserDefaults.standard.set(fp, forKey: fingerprintKey)
                phase = .connected
                Haptics.success()
                startLoop()
            } catch {
                client.close()
                challenge = nil
                if case SSHError.cancelled = error { loginError = nil } else { loginError = error.localizedDescription; Haptics.error() }
                phase = .loggedOut
            }
        }
    }

    /// Runs on the SSH queue: shows the prompt and blocks until the user answers or cancels.
    nonisolated private func askUser(_ c: AuthChallenge) -> [String]? {
        let done = DispatchSemaphore(value: 0)
        let result = Box()
        Task { @MainActor in
            self.answerBox = { answers in result.answers = answers; done.signal() }
            self.challenge = c
        }
        done.wait()
        return result.answers
    }

    func answer(_ answers: [String]?) {
        challenge = nil
        answerBox?(answers)
        answerBox = nil
    }

    func disconnect() {
        loop?.cancel(); loop = nil
        if challenge != nil { answer(nil) }
        client.close()
        jobs = nil; allocations = nil; jobsUpdated = nil; allocationsUpdated = nil
        demo = false
        phase = .loggedOut
    }

    func showDemo() {
        demo = true
        jobs = JobsSnapshot(squeue: DemoData.squeue)
        allocations = AllocationsSnapshot(output: DemoData.allocations)
        jobsUpdated = .now; allocationsUpdated = .now
        phase = .connected
    }

    // MARK: - polling

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            var lastJobs = Date.distantPast, lastAlloc = Date.distantPast, lastPing = Date.now
            while !Task.isCancelled, let self, self.phase == .connected {
                do {
                    if self.inBackground {
                        // Nobody is looking: just keep the session alive.
                        if Date.now.timeIntervalSince(lastPing) > 20 { try await self.client.keepalive(); lastPing = .now }
                    } else {
                        if Date.now.timeIntervalSince(lastJobs) >= self.jobsInterval {
                            lastJobs = .now
                            try await self.refreshJobs()
                        }
                        if Date.now.timeIntervalSince(lastAlloc) >= self.allocationsInterval {
                            lastAlloc = .now
                            try await self.refreshAllocations()
                        }
                        lastPing = .now
                    }
                } catch {
                    self.connectionLost(error)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func refreshNow() async {
        guard phase == .connected, !demo else { return }
        do {
            try await refreshJobs()
            try await refreshAllocations()
        } catch { connectionLost(error) }
    }

    /// One user's jobs across every account (`squeue -u`), for their page.
    func userJobs(_ user: String) async throws -> UserJobsSnapshot {
        if demo { return UserJobsSnapshot(user: user, output: DemoData.userJobs(user)) }
        guard phase == .connected else { throw SSHError.libssh2("Not connected") }
        guard let cmd = Slurm.userJobsCommand(user) else { throw SSHError.libssh2("Unexpected username \(user)") }
        return UserJobsSnapshot(user: user, output: try await client.exec(cmd))
    }

    private func refreshJobs() async throws {
        let out = try await client.exec(Slurm.jobsCommand)
        jobs = JobsSnapshot(squeue: out)
        jobsUpdated = .now
    }

    private func refreshAllocations() async throws {
        let out = try await client.exec(Slurm.allocationsCommand)
        allocations = AllocationsSnapshot(output: out)
        allocationsUpdated = .now
    }

    private func connectionLost(_ error: Error) {
        loop?.cancel(); loop = nil
        client.close()
        phase = .lost(error.localizedDescription)
        Haptics.error()
    }

    // MARK: - app lifecycle

    func scenePhaseChanged(_ p: ScenePhase) {
        switch p {
        case .background:
            inBackground = true
            // Even with the setting off, don't let iOS suspend a login while you approve Duo.
            keeper.enteredBackground(force: phase == .connecting)
        case .active:
            let wasBackground = inBackground
            inBackground = false
            keeper.enteredForeground()
            if wasBackground, phase == .connected, !demo { Task { await refreshNow() } }
        default: break
        }
    }
}

private final class Flag: @unchecked Sendable { var value = false }
private final class Box: @unchecked Sendable { var answers: [String]? }
