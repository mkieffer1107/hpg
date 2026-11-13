import Foundation

// The remote commands hpg runs (squeue, sacctmgr, blue_quota, sinfo; all read-only) and their parsers.

enum Slurm {
    /// Your jobs, one per line: `%i|%P|%j|%a|%q|%T|%M|%l|%C|%m|%b|%R`.
    static let jobsCommand = #"squeue -u "$USER" -h -o "%i|%P|%j|%a|%q|%T|%M|%l|%C|%m|%b|%R""#

    /// Everything the allocations screen needs, in `##SECTION` blocks (sacctmgr, squeue -A, blue_quota, sinfo).
    static let allocationsCommand: String = {
        let script = #"""
        q=$(sacctmgr -nP show qos format=Name,GrpTRES 2>/dev/null)
        sel=""
        for g in $(id -Gn); do grep -q "^${g}|" <<<"$q" && sel="$sel $g"; done
        acct=$(echo $sel | tr ' ' ,)
        echo "##ME"; whoami
        echo "##GROUPS"; echo $sel
        echo "##QOS"; for g in $sel; do grep -E "^${g}(-b)?\|" <<<"$q"; done
        echo "##JOBS"; [ -n "$acct" ] && squeue -h -r -A "$acct" -O "Account:40,UserName:40,StateCompact:6,QOS:40,tres-alloc:250" 2>/dev/null
        echo "##QUOTA"; for g in $sel; do echo "$g $(blue_quota -g "$g" 2>/dev/null | awk '$1 ~ /^blue/ {print $2, $3; exit}')"; done
        echo "##GPUS"; sinfo -h -N -O "NodeList:30,Gres:60,GresUsed:80,StateCompact:14" 2>/dev/null | grep "gpu:"
        """#
        // Ship it base64-encoded so the login shell's quoting rules never matter.
        return "echo \(Data(script.utf8).base64EncodedString()) | base64 -d | bash"
    }()

    // MARK: - time and size helpers

    /// "1-02:03:04", "02:03:04", "03:04" -> seconds.
    static func seconds(_ t: String) -> Int {
        var days = 0, rest = Substring(t)
        if let dash = t.firstIndex(of: "-") { days = Int(t[..<dash]) ?? 0; rest = t[t.index(after: dash)...] }
        let p = rest.split(separator: ":").map { Int($0) ?? 0 }
        let s = p.count == 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p.count == 2 ? p[0] * 60 + p[1] : (p.first ?? 0) * 60
        return days * 86400 + s
    }

    /// "32G", "500M", "1.5T", "4000" (MB) -> GB.
    static func gigabytes(_ s: String) -> Double {
        guard let last = s.last else { return 0 }
        let unit = Character(last.uppercased())   // blue_quota prints "116k"
        if last.isNumber { return (Double(s) ?? 0) / 1024 }   // plain number = MB
        let n = Double(s.dropLast()) ?? 0
        switch unit {
        case "T": return n * 1024
        case "G": return n
        case "M": return n / 1024
        case "K": return n / 1_048_576
        default: return n / 1024
        }
    }

    /// 10800 -> "3h 0m", 2400 -> "40m", 93784 -> "1d 2h", 38 -> "38s".
    static func human(_ secs: Int) -> String {
        let d = secs / 86400, h = secs % 86400 / 3600, m = secs % 3600 / 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(secs)s"
    }

    /// A limit like "12:00:00" -> "12h", "1-00:00:00" -> "1d", "40:00" -> "40m".
    static func humanLimit(_ t: String) -> String {
        let s = seconds(t)
        return s % 3600 == 0 && s < 86400 ? "\(s / 3600)h" : human(s)
    }

    /// squeue's pending reason in plain words; unknown reasons come back unchanged.
    static func reasonText(_ r: String) -> String {
        let key = r.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        switch key {
        case "Dependency": return "waiting on another job"
        case "DependencyNeverSatisfied": return "dependency failed, will never start"
        case "Priority": return "in line (others have priority)"
        case "Resources": return "next up, waiting for free nodes"
        case "QOSGrpCpuLimit": return "group CPU limit reached"
        case "QOSGrpMemLimit": return "group memory limit reached"
        case "QOSGrpGRES": return "group GPU limit reached"
        case "QOSMaxJobsPerUserLimit", "QOSMaxSubmitJobPerUserLimit": return "your job-count limit reached"
        case "JobArrayTaskLimit": return "array running max tasks at once"
        case "BeginTime": return "scheduled for later"
        case "ReqNodeNotAvail", "ReqNodeNotAvail, Reserved for maintenance": return "nodes unavailable (maintenance?)"
        case "JobHeldUser": return "held by you"
        case "JobHeldAdmin": return "held by an admin"
        case "None": return "just submitted"
        default: return key
        }
    }

    static func formatGB(_ g: Double) -> String {
        g >= 1024 ? String(format: "%.1fT", g / 1024) : "\(Int(g.rounded()))G"
    }
}

// MARK: - jobs

struct Job {
    let id, partition, name, account, qos, state, time, limit: String
    let cpus: Int
    let memGB: Double
    let gpu: String          // "b200:4" or "-"
    let gpusPerTask: Int
    let whereOrWhy: String   // node list when running, (Reason) when pending
    let tasks: Int           // a pending array line like 123_[4-9] stands for several tasks

    var isBurst: Bool { qos.hasSuffix("-b") }

    init?(line: Substring) {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 12 else { return nil }
        id = f[0]; name = f[2]; account = f[3]; qos = f[4]; state = f[5]; time = f[6]; limit = f[7]
        cpus = Int(f[8]) ?? 0
        memGB = Slurm.gigabytes(f[9])
        whereOrWhy = f[11]
        // "hpg-default,hpg-milan,hpg-turin" -> "default+2"
        let parts = f[1].split(separator: ",")
        var p = String(parts.first ?? "")
        if p.hasPrefix("hpg-") { p.removeFirst(4) }
        partition = parts.count > 1 ? "\(p)+\(parts.count - 1)" : p
        var g = f[10]
        if g.hasPrefix("gres/gpu") { g = String(g.dropFirst(8)).trimmingCharacters(in: [":"]) }
        if g.isEmpty || g == "N/A" { g = "-" }
        gpu = g
        gpusPerTask = g == "-" ? 0 : Int(g.split(separator: ":").last ?? "") ?? 1
        tasks = Job.taskCount(id)
    }

    /// "123_[4-9,12%4]" -> 7; anything else -> 1.
    static func taskCount(_ id: String) -> Int {
        guard let open = id.range(of: "_[") else { return 1 }
        let body = id[open.upperBound...].prefix { $0 != "]" && $0 != "%" }
        return body.split(separator: ",").reduce(0) { n, r in
            let ab = r.split(separator: "-").compactMap { Int($0) }
            return n + (ab.count == 2 ? ab[1] - ab[0] + 1 : 1)
        }
    }
}

/// One line on the jobs screen: a single job, or 3+ look-alike jobs merged into one.
struct JobRow: Identifiable {
    let id: String
    let jobID: String?       // nil for a merged row
    let count: Int
    let name, partition, account, state, time, limit, gpu, whereOrWhy: String
    let cpus: Int
    let memGB: Double
    let gpus: Int
    let isBurst: Bool

    /// "b200" for gres/gpu:b200:4, "GPU" when the job didn't ask for a type.
    var gpuType: String { gpu.contains(":") ? String(gpu.split(separator: ":")[0]) : "GPU" }

    var progress: Double? {
        let l = Slurm.seconds(limit)
        return state == "RUNNING" && l > 0 ? min(1, Double(Slurm.seconds(time)) / Double(l)) : nil
    }
}

struct JobsSnapshot {
    var main: [JobRow] = []
    var burst: [JobRow] = []
    var running = 0, pending = 0, total = 0, burstCount = 0
    var gpusRunning = 0, gpusPending = 0

    /// Non-burst jobs first, burst jobs separately; 3+ jobs with the same
    /// name/account/QOS/state/shape collapse into one row.
    init(squeue output: String) {
        let jobs = output.split(separator: "\n").compactMap(Job.init(line:)).sorted {
            if $0.state != $1.state { return $0.state > $1.state }   // RUNNING before PENDING
            return Self.numericID($0.id) < Self.numericID($1.id)
        }
        var order: [String] = []
        var groups: [String: [Job]] = [:]
        for j in jobs {
            let key = [j.isBurst ? "b" : "", j.name, j.account, j.qos, j.state, j.partition, j.limit,
                       String(j.cpus), String(j.memGB), j.gpu].joined(separator: "|")
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(j)
            if j.state == "RUNNING" { running += j.tasks; gpusRunning += j.tasks * j.gpusPerTask }
            else if j.state == "PENDING" { pending += j.tasks; gpusPending += j.tasks * j.gpusPerTask }
            total += j.tasks
            if j.isBurst { burstCount += j.tasks }
        }
        for key in order {
            let g = groups[key]!
            let n = g.reduce(0) { $0 + $1.tasks }
            let rows: [JobRow]
            if n < 3 {
                rows = g.map { j in
                    JobRow(id: j.id, jobID: j.id, count: j.tasks, name: j.name, partition: j.partition, account: j.account,
                           state: j.state, time: j.time, limit: j.limit, gpu: j.gpu, whereOrWhy: j.whereOrWhy,
                           cpus: j.cpus * j.tasks, memGB: j.memGB * Double(j.tasks), gpus: j.gpusPerTask * j.tasks, isBurst: j.isBurst)
                }
            } else {
                let f = g[0]
                let longest = g.max { Slurm.seconds($0.time) < Slurm.seconds($1.time) }!.time
                let places = Set(g.map(\.whereOrWhy))
                let where_ = places.count == 1 ? f.whereOrWhy
                    : f.state == "RUNNING" ? "\(places.count) nodes" : "\(places.count) reasons"
                rows = [JobRow(id: key, jobID: nil, count: n, name: f.name, partition: f.partition, account: f.account,
                               state: f.state, time: longest, limit: f.limit, gpu: f.gpu, whereOrWhy: where_,
                               cpus: g.reduce(0) { $0 + $1.cpus * $1.tasks },
                               memGB: g.reduce(0) { $0 + $1.memGB * Double($1.tasks) },
                               gpus: n * f.gpusPerTask, isBurst: f.isBurst)]
            }
            if g[0].isBurst { burst += rows } else { main += rows }
        }
    }

    private static func numericID(_ id: String) -> Int { Int(id.prefix { $0.isNumber }) ?? 0 }
}

// MARK: - allocations

struct UserUsage: Identifiable {
    var id: String { name }
    let name: String
    var isMe = false
    var cpu = 0, gpu = 0, pCpu = 0, pGpu = 0, pJobs = 0
    var mem = 0.0, pMem = 0.0
}

struct GroupAlloc: Identifiable {
    var id: String { name }
    let name: String
    var cpu = 0, cpuLimit = 0, gpu = 0, gpuLimit = 0
    var mem = 0.0, memLimit = 0.0
    var pCpu = 0, pGpu = 0, pJobs = 0
    var pMem = 0.0
    var burstCpu = 0, burstLimit = 0
    var quotaUsed = "?", quotaLimit = "?"
    var quotaFraction: Double {
        let l = Slurm.gigabytes(quotaLimit)
        return l > 0 ? Slurm.gigabytes(quotaUsed) / l : 0
    }
    var users: [UserUsage] = []
}

struct GPUType: Identifiable {
    var id: String { name }
    let name: String
    var free = 0, total = 0, up = 0
}

struct AllocationsSnapshot {
    var me = ""
    var groups: [GroupAlloc] = []
    var gpuTypes: [GPUType] = []

    init(output: String) {
        var section = ""
        var limits: [String: (cpu: Int, mem: Double, gpu: Int)] = [:]
        var byName: [String: GroupAlloc] = [:]
        var order: [String] = []
        var users: [String: [String: UserUsage]] = [:]
        var userOrder: [String: [String]] = [:]
        var gpus: [String: GPUType] = [:]
        var gpuOrder: [String] = []
        var seenNodes = Set<String>()

        func tres(_ s: Substring, _ key: String) -> String? {
            for kv in s.split(separator: ",") {
                let p = kv.split(separator: "=", maxSplits: 1)
                if p.count == 2 && p[0] == key { return String(p[1]) }
            }
            return nil
        }

        for line in output.split(separator: "\n") {
            if line.hasPrefix("##") { section = String(line); continue }
            let w = line.split(separator: " ", omittingEmptySubsequences: true)
            switch section {
            case "##ME": me = String(line).trimmingCharacters(in: .whitespaces)
            case "##GROUPS":
                order = w.map(String.init)
                for g in order { byName[g] = GroupAlloc(name: g) }
            case "##QOS":
                let p = line.split(separator: "|", maxSplits: 1)
                guard p.count == 2 else { continue }
                limits[String(p[0])] = (Int(tres(p[1], "cpu") ?? "") ?? 0,
                                        Slurm.gigabytes(tres(p[1], "mem") ?? "0G"),
                                        Int(tres(p[1], "gres/gpu") ?? "") ?? 0)
            case "##JOBS":
                guard w.count >= 5, byName[String(w[0])] != nil else { continue }
                let a = String(w[0]), u = String(w[1]), st = w[2], qos = w[3], t = w[4]
                let cpu = Int(tres(t, "cpu") ?? "") ?? 0
                let mem = Slurm.gigabytes(tres(t, "mem") ?? "0G")
                let gpu = Int(tres(t, "gres/gpu") ?? "") ?? 0
                let running = st == "R" || st == "CG"
                guard running || st == "PD" else { continue }
                if users[a]?[u] == nil {
                    users[a, default: [:]][u] = UserUsage(name: u)
                    userOrder[a, default: []].append(u)
                }
                if qos.hasSuffix("-b") {
                    if running { byName[a]!.burstCpu += cpu } else { byName[a]!.pCpu += cpu; byName[a]!.pMem += mem; byName[a]!.pJobs += 1 }
                } else if running {
                    byName[a]!.cpu += cpu; byName[a]!.mem += mem; byName[a]!.gpu += gpu
                } else {
                    byName[a]!.pCpu += cpu; byName[a]!.pMem += mem; byName[a]!.pGpu += gpu; byName[a]!.pJobs += 1
                }
                if running {
                    users[a]![u]!.cpu += cpu; users[a]![u]!.mem += mem; users[a]![u]!.gpu += gpu
                } else {
                    users[a]![u]!.pCpu += cpu; users[a]![u]!.pMem += mem; users[a]![u]!.pGpu += gpu; users[a]![u]!.pJobs += 1
                }
            case "##QUOTA":
                guard w.count >= 3, byName[String(w[0])] != nil else { continue }
                byName[String(w[0])]!.quotaUsed = String(w[1]); byName[String(w[0])]!.quotaLimit = String(w[2])
            case "##GPUS":
                guard w.count >= 4, !seenNodes.contains(String(w[0])) else { continue }
                seenNodes.insert(String(w[0]))
                let st = w[3]
                let ok = ["idle", "mix", "alloc", "comp"].contains { st.hasPrefix($0) } && !st.contains("$")
                let gres = w[1].split(separator: ","), used = w[2].split(separator: ",")
                for (i, gr) in gres.enumerated() where gr.hasPrefix("gpu:") {
                    let p = gr.split(whereSeparator: { $0 == ":" || $0 == "(" })
                    guard p.count >= 3 else { continue }
                    let type = String(p[1]), tot = Int(p[2]) ?? 0
                    var u = 0
                    if i < used.count {
                        let q = used[i].split(whereSeparator: { $0 == ":" || $0 == "(" })
                        if q.count >= 3 { u = Int(q[2]) ?? 0 }
                    }
                    if gpus[type] == nil { gpus[type] = GPUType(name: type); gpuOrder.append(type) }
                    gpus[type]!.total += tot
                    if ok { gpus[type]!.free += tot - u; gpus[type]!.up += tot }
                }
            default: break
            }
        }

        groups = order.compactMap { name in
            guard var g = byName[name] else { return nil }
            if let l = limits[name] { g.cpuLimit = l.cpu; g.memLimit = l.mem; g.gpuLimit = l.gpu }
            g.burstLimit = limits[name + "-b"]?.cpu ?? 0
            g.users = (userOrder[name] ?? []).map { u in
                var usage = users[name]![u]!
                usage.isMe = u == me
                return usage
            }
            return g
        }
        gpuTypes = gpuOrder.compactMap { gpus[$0] }
    }

    init() {}
}
