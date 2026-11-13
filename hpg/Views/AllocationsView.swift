import SwiftUI

/// green < 50% of the limit, yellow 50–90%, red > 90% ; pink = used with no limit.
func usageColor(_ used: Double, _ limit: Double) -> Color {
    guard limit > 0 else { return used > 0 ? .pink : .secondary }
    let r = used / limit
    return r >= 0.9 ? .red : r >= 0.5 ? .yellow : .green
}

extension GroupAlloc {
    var me: UserUsage? { users.first(where: \.isMe) }
    var isMine: Bool { me != nil }
}

/// "104 CPU · 440 GB · 2 GPUs"
func resourceText(cpu: Int, mem: Double, gpu: Int, jobs: Int? = nil) -> String {
    var parts = ["\(cpu) CPU", "\(Int(mem.rounded())) GB"]
    if gpu > 0 { parts.append("\(gpu) GPU\(gpu == 1 ? "" : "s")") }
    if let jobs { parts.append("\(jobs) job\(jobs == 1 ? "" : "s")") }
    return parts.joined(separator: " · ")
}

struct AllocationsView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        List {
            if let a = monitor.allocations {
                if !a.gpuTypes.isEmpty {
                    Section {
                        HStack(spacing: 8) {
                            ForEach(a.gpuTypes) { GPUFreeTile(gpu: $0) }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("GPUs free on the cluster")
                    }
                }

                let mine = a.groups.filter(\.isMine), others = a.groups.filter { !$0.isMine }
                if !mine.isEmpty {
                    Section {
                        ForEach(mine) { GroupLink(group: $0) }
                    } header: {
                        Text("Groups you're using")
                    }
                }
                if !others.isEmpty {
                    Section {
                        ForEach(others) { GroupLink(group: $0) }
                    } header: {
                        Text(mine.isEmpty ? "Your groups" : "Your other groups")
                    } footer: {
                        Text("Bars show what's running against each group's limit: green under 50%, yellow 50–90%, red over 90%. Tap a group to see who is using it.")
                    }
                }
            } else {
                HStack { Spacer(); ProgressView("Loading allocations…"); Spacer() }
                    .listRowBackground(Color.clear)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Allocations")
        .navigationDestination(for: String.self) { GroupDetailView(name: $0).onAppear { Haptics.tap() } }
        .refreshable { await monitor.refreshNow(); Haptics.tap() }
    }
}

struct GPUFreeTile: View {
    let gpu: GPUType

    var body: some View {
        let ratio = gpu.up > 0 ? Double(gpu.free) / Double(gpu.up) : 0
        let color: Color = ratio >= 0.1 ? .green : gpu.free > 0 ? .yellow : .red
        VStack(alignment: .leading, spacing: 4) {
            Text(gpu.name.replacingOccurrences(of: "_", with: " "))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(gpu.free)").font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(color)
                    .contentTransition(.numericText())
                Text("free").font(.caption).foregroundStyle(color)
            }
            Text("of \(gpu.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
}

/// One group on the main screen: name, five small labelled gauges, and your share in words.
struct GroupLink: View {
    let group: GroupAlloc

    var body: some View {
        NavigationLink(value: group.name) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.name).font(.headline)
                    Spacer()
                    if group.pJobs > 0 {
                        Text("\(group.pJobs) waiting").font(.caption.weight(.medium)).foregroundStyle(.cyan)
                    }
                }
                HStack(spacing: 10) {
                    MiniGauge(label: "CPU", used: Double(group.cpu), limit: Double(group.cpuLimit))
                    MiniGauge(label: "Memory", used: group.mem, limit: group.memLimit)
                    MiniGauge(label: "GPU", used: Double(group.gpu), limit: Double(group.gpuLimit))
                    MiniGauge(label: "Burst", used: Double(group.burstCpu), limit: Double(group.burstLimit))
                    MiniGauge(label: "/blue", used: group.quotaFraction, limit: group.quotaLimit == "?" ? 0 : 1)
                }
                if let me = group.me {
                    YouLine(user: me)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct MiniGauge: View {
    let label: String
    let used: Double
    let limit: Double

    var body: some View {
        let p = limit > 0 ? 100 * used / limit : 0
        let text = limit <= 0 ? "–" : (used > 0 && p < 0.5) ? "<1%" : "\(Int(p.rounded()))%"
        let color = usageColor(used, limit)
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(text).font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(used > 0 && limit > 0 ? color : .secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if limit > 0 && used > 0 {
                        Capsule().fill(color.gradient).frame(width: max(3, geo.size.width * min(1, used / limit)))
                    }
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "You: 104 CPU · 440 GB running, 5 jobs waiting"
struct YouLine: View {
    let user: UserUsage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            YouBadge()
            VStack(alignment: .leading, spacing: 2) {
                if user.cpu > 0 || user.gpu > 0 {
                    Text("\(resourceText(cpu: user.cpu, mem: user.mem, gpu: user.gpu)) running")
                }
                if user.pJobs > 0 {
                    Text("\(user.pJobs) job\(user.pJobs == 1 ? "" : "s") waiting").foregroundStyle(.cyan)
                }
            }
            .font(.caption.monospacedDigit())
        }
    }
}

struct YouBadge: View {
    var body: some View {
        Text("YOU")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.accentColor, in: .capsule)
    }
}

// MARK: - one group

struct GroupDetailView: View {
    @Environment(Monitor.self) private var monitor
    let name: String

    var body: some View {
        List {
            if let g = monitor.allocations?.groups.first(where: { $0.name == name }) {
                Section {
                    Meter(label: "CPU cores", used: Double(g.cpu), limit: Double(g.cpuLimit), text: "\(g.cpu) of \(g.cpuLimit)")
                    Meter(label: "Memory", used: g.mem, limit: g.memLimit,
                          text: "\(Int(g.mem.rounded())) of \(Int(g.memLimit.rounded())) GB")
                    if g.gpuLimit > 0 || g.gpu > 0 {
                        Meter(label: "GPUs", used: Double(g.gpu), limit: Double(g.gpuLimit), text: "\(g.gpu) of \(g.gpuLimit)")
                    }
                } header: {
                    Text("Running now (investment QOS)")
                } footer: {
                    Text("Jobs here can run up to 31 days.")
                }

                Section {
                    if g.users.isEmpty {
                        Text("Nobody is running or waiting in this group.").foregroundStyle(.secondary)
                    } else {
                        ForEach(g.users.sorted { $0.isMe && !$1.isMe }) { UserCard(user: $0) }
                    }
                } header: {
                    Text("Who is using it")
                } footer: {
                    Text("Submit with: sbatch --account=\(g.name) --qos=\(g.name)   (burst: --qos=\(g.name)-b)")
                        .font(.caption2.monospaced())
                }

                if g.burstLimit > 0 {
                    Section {
                        Meter(label: "Burst CPU cores", used: Double(g.burstCpu), limit: Double(g.burstLimit),
                              text: "\(g.burstCpu) of \(g.burstLimit)")
                    } footer: {
                        Text("Burst (\(g.name)-b) uses idle CPUs only, no GPUs, up to 4 days.")
                    }
                }

                if g.pJobs > 0 {
                    Section("Waiting in the queue") {
                        Text(resourceText(cpu: g.pCpu, mem: g.pMem, gpu: g.pGpu, jobs: g.pJobs))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.cyan)
                    }
                }

                Section("Storage") {
                    Meter(label: "/blue/\(g.name)", used: g.quotaFraction, limit: 1,
                          text: "\(g.quotaUsed) of \(g.quotaLimit)", hasUsage: g.quotaUsed != "?")
                }

            } else {
                Text("This group is no longer in the report.").foregroundStyle(.secondary)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await monitor.refreshNow(); Haptics.tap() }
    }
}

struct Meter: View {
    let label: String
    let used: Double
    let limit: Double
    let text: String
    var hasUsage: Bool? = nil

    var body: some View {
        let r = limit > 0 ? used / limit : (used > 0 ? 1 : 0)
        let color = usageColor(used, limit)
        let showColor = hasUsage ?? (used > 0)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline)
                Spacer()
                Text(text).font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(showColor && used > 0 ? color : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color.gradient).frame(width: max(used > 0 ? 4 : 0, geo.size.width * min(1, r)))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }
}

/// One person in "Who is using it": full name, then running and waiting in words.
struct UserCard: View {
    let user: UserUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: user.isMe ? "person.crop.circle.fill" : "person.crop.circle")
                    .foregroundStyle(user.isMe ? Color.accentColor : .secondary)
                Text(user.name).font(.subheadline.weight(.semibold))
                if user.isMe { YouBadge() }
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                if user.cpu > 0 || user.gpu > 0 || user.mem > 0 {
                    GridRow {
                        Text("Running").foregroundStyle(.green)
                        Text(resourceText(cpu: user.cpu, mem: user.mem, gpu: user.gpu))
                    }
                }
                if user.pJobs > 0 {
                    GridRow {
                        Text("Waiting").foregroundStyle(.cyan)
                        Text(resourceText(cpu: user.pCpu, mem: user.pMem, gpu: user.pGpu, jobs: user.pJobs))
                    }
                }
            }
            .font(.caption.monospacedDigit())
        }
        .padding(.vertical, 3)
        .listRowBackground(user.isMe ? Color.accentColor.opacity(0.12) : nil)
    }
}
