import SwiftUI

/// Navigation value for a person's page (kept distinct from group names, which are plain Strings).
struct UserRoute: Hashable { let name: String }

/// Everything one person is running or waiting on, in every account: `squeue -u <user>`.
struct UserJobsView: View {
    @Environment(Monitor.self) private var monitor
    let user: String
    @State private var snapshot: UserJobsSnapshot?
    @State private var error: String?

    private var isMe: Bool { user == monitor.allocations?.me }

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
            }

            if let s = snapshot {
                Section {
                    HStack(spacing: 8) {
                        StatTile(value: s.jobs.running, label: "running", color: .green)
                        StatTile(value: s.jobs.pending, label: "waiting", color: .yellow)
                        StatTile(value: s.gpu, label: "GPUs in use", color: .purple)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if s.jobs.total > 0 {
                        Text("\(s.cpu) CPU · \(Slurm.formatGB(s.mem)) running · \(s.jobs.total) jobs in all")
                            .font(.caption.monospacedDigit())
                    }
                }

                if s.jobs.total == 0 {
                    ContentUnavailableView("No jobs", systemImage: "tray",
                                           description: Text("\(user) has nothing running or queued."))
                } else {
                    Section("By account") {
                        ForEach(s.accounts) { AccountRow(account: $0) }
                    }
                    if !s.jobs.main.isEmpty {
                        Section("Jobs") { ForEach(s.jobs.main) { JobRowView(row: $0) } }
                    }
                    if !s.jobs.burst.isEmpty {
                        Section {
                            ForEach(s.jobs.burst) { JobRowView(row: $0) }
                        } header: {
                            Label("Burst · \(s.jobs.burstCount) jobs", systemImage: "bolt.fill").textCase(nil)
                        }
                    }
                }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.footnote)
            } else {
                HStack { Spacer(); ProgressView("Loading \(user)'s jobs…"); Spacer() }
                    .listRowBackground(Color.clear)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(user)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(); Haptics.tap() }
        .task {
            // Refresh while the page is open, on the same schedule as your own jobs.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(max(5, monitor.jobsInterval)))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(initials)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background((isMe ? Color.accentColor : Color.gray).gradient, in: .circle)
            HStack(spacing: 6) {
                Text(snapshot?.realName ?? user).font(.title3.bold())
                if isMe { YouBadge() }
            }
            if snapshot?.realName != nil {
                Text(user).font(.subheadline.monospaced()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var initials: String {
        let source = snapshot?.realName ?? user
        let words = source.split(whereSeparator: { " ._-".contains($0) })
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private func load() async {
        do {
            snapshot = try await monitor.userJobs(user)
            error = nil
        } catch {
            if snapshot == nil { self.error = error.localizedDescription }
        }
    }
}

/// One account in a person's "By account" list: what they hold there right now, and what's queued.
private struct AccountRow: View {
    let account: AccountUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(account.name.replacingOccurrences(of: " burst", with: ""))
                    .font(.subheadline.weight(.semibold))
                if account.burst {
                    Label("burst", systemImage: "bolt.fill")
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if account.gpu > 0 {
                    Text("\(account.gpu) GPU\(account.gpu == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.purple)
                }
            }
            HStack(spacing: 10) {
                if account.running > 0 {
                    Text("\(account.running) running · \(account.cpu) CPU · \(Slurm.formatGB(account.mem))")
                        .foregroundStyle(.green)
                }
                if account.pending > 0 {
                    Text("\(account.pending) waiting\(account.pGpu > 0 ? " · \(account.pGpu) GPU" : "")")
                        .foregroundStyle(.cyan)
                }
            }
            .font(.caption.monospacedDigit())
        }
        .padding(.vertical, 2)
    }
}
