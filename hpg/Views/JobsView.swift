import SwiftUI

struct JobsView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        List {
            if let j = monitor.jobs {
                Section {
                    HStack(spacing: 8) {
                        StatTile(value: j.running, label: "running", color: .green)
                        StatTile(value: j.pending, label: "pending", color: .yellow)
                        StatTile(value: j.gpusRunning, label: "GPUs in use", color: .purple)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text(summary(j)).font(.caption.monospacedDigit())
                }

                if j.total == 0 {
                    ContentUnavailableView("No jobs", systemImage: "tray", description: Text("Nothing running or queued."))
                }
                if !j.main.isEmpty {
                    Section {
                        ForEach(j.main) { JobRowView(row: $0) }
                    } header: {
                        Text("Investment QOS · \(j.total - j.burstCount) jobs").textCase(nil)
                    }
                }
                if !j.burst.isEmpty {
                    Section {
                        ForEach(j.burst) { JobRowView(row: $0) }
                    } header: {
                        Label("Burst · \(j.burstCount) jobs", systemImage: "bolt.fill")
                            .textCase(nil)
                    } footer: {
                        Text("<group>-b QOS: idle CPUs only, no GPUs, up to 4 days.")
                    }
                }
            } else {
                HStack { Spacer(); ProgressView("Loading jobs…"); Spacer() }
                    .listRowBackground(Color.clear)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Jobs")
        .refreshable { await monitor.refreshNow(); Haptics.tap() }
    }

    private func summary(_ j: JobsSnapshot) -> String {
        var s = "\(j.total) total"
        if j.burstCount > 0 { s += " · \(j.burstCount) burst" }
        if j.gpusPending > 0 { s += " · \(j.gpusPending) GPUs pending" }
        return s
    }
}

struct StatTile: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(value > 0 ? color : .secondary)
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}

struct JobRowView: View {
    let row: JobRow

    var body: some View {
        let running = row.state == "RUNNING"
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if row.jobID == nil {
                    Text("×\(row.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                }
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                StatePill(state: row.state)
            }

            HStack(spacing: 6) {
                Chip(text: "\(row.cpus) CPU")
                Chip(text: Slurm.formatGB(row.memGB))
                if row.gpus > 0 {
                    Chip(text: "\(row.gpus)× \(row.gpuType)", tint: .purple)
                }
                Spacer(minLength: 4)
                if running {
                    Text("\(Slurm.human(Slurm.seconds(row.time))) of \(Slurm.humanLimit(row.limit))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("up to \(Slurm.humanLimit(row.limit))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            if let p = row.progress {
                ProgressView(value: p).tint(p > 0.9 ? .red : p > 0.75 ? .orange : .green)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if running {
                    let left = max(0, Slurm.seconds(row.limit) - Slurm.seconds(row.time))
                    IconText(icon: "timer", text: "\(Slurm.human(left)) left")
                        .foregroundStyle(left < 1800 ? .red : .secondary)
                    Spacer(minLength: 4)
                    Text(row.whereOrWhy).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                } else {
                    IconText(icon: "hourglass", text: Slurm.reasonText(row.whereOrWhy))
                        .foregroundStyle(.orange)
                    Spacer(minLength: 4)
                }
            }
            .font(.caption)

            Text([row.jobID ?? "\(row.count) jobs", row.partition, row.account].joined(separator: " · "))
                .font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}

struct StatePill: View {
    let state: String

    var body: some View {
        Text(state.lowercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }

    private var color: Color {
        switch state {
        case "RUNNING": return .green
        case "PENDING": return .orange
        case let s where ["FAIL", "CANCEL", "TIMEOUT", "OUT_OF_MEMORY", "NODE_FAIL"].contains(where: s.contains): return .red
        default: return .cyan
        }
    }
}

struct Chip: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit().weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(tint == .secondary ? Color.primary : tint)
            .background((tint == .secondary ? Color.gray : tint).opacity(0.15), in: .rect(cornerRadius: 5))
    }
}

/// An SF Symbol and text with a tight gap (Label's gap is wide at caption sizes).
struct IconText: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).imageScale(.small)
            Text(text).lineLimit(1)
        }
    }
}
