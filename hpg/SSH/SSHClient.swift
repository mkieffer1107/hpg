import CSSH
import Foundation

/// One prompt round of keyboard-interactive auth (HiPerGator asks for the password, then Duo).
struct AuthChallenge: Identifiable {
    struct Prompt { let text: String; let echo: Bool }
    let id = UUID()
    let name: String
    let instruction: String
    let prompts: [Prompt]

    /// Duo's numbered menu: " 1. Duo Push to XXX-XXX-1234" -> ("1", "Duo Push to XXX-XXX-1234").
    var options: [(key: String, label: String)] {
        let text = ([instruction] + prompts.map(\.text)).joined(separator: "\n")
        return text.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let dot = t.firstIndex(of: "."), let n = Int(t[..<dot]), n < 10 else { return nil }
            let label = t[t.index(after: dot)...].trimmingCharacters(in: .whitespaces)
            return label.isEmpty ? nil : (String(n), label)
        }
    }

    /// The menu number for "Duo Push", if this is Duo's menu and it offers a push.
    var pushOption: String? {
        guard prompts.count == 1 else { return nil }
        return options.first { $0.label.lowercased().contains("push") }?.key
    }
}

enum SSHError: LocalizedError {
    case connect(String)
    case libssh2(String)
    case hostKeyChanged(expected: String, got: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .connect(let m): return m
        case .libssh2(let m): return m
        case .hostKeyChanged(let e, let g):
            return "The server's host key changed (expected \(e.prefix(16))…, got \(g.prefix(16))…). Not connecting. Reset it in Settings if you trust the change."
        case .cancelled: return "Login cancelled"
        }
    }
}

/// A blocking libssh2 session. Every call runs on one serial queue, so the session is
/// never touched from two threads; the async wrappers hop onto that queue.
final class SSHClient: @unchecked Sendable {
    typealias Answerer = @Sendable (AuthChallenge) -> [String]?

    private let queue = DispatchQueue(label: "ssh.session")
    private var session: OpaquePointer?
    private var sock: Int32 = -1
    private var answerer: Answerer?
    private var authCancelled = false

    private static let initOnce: Void = { libssh2_init(0) }()

    /// Connects, verifies the host key against `knownFingerprint` (trust on first use) and logs in
    /// with keyboard-interactive auth. `answer` is called on the SSH queue for each prompt round and
    /// may block while the user types; return nil to cancel. Returns the host key fingerprint.
    func connect(host: String, port: Int = 22, user: String, knownFingerprint: String?,
                 answer: @escaping Answerer) async throws -> String {
        try await run { [self] in
            _ = Self.initOnce
            closeLocked()
            sock = try Self.openSocket(host: host, port: port)

            // `abstract` points back at self so the C auth callback can reach the answerer.
            guard let s = libssh2_session_init_ex(nil, nil, nil, Unmanaged.passUnretained(self).toOpaque()) else {
                throw SSHError.libssh2("libssh2_session_init failed")
            }
            session = s
            libssh2_session_set_blocking(s, 1)
            libssh2_session_set_timeout(s, 20_000)
            guard libssh2_session_handshake(s, sock) == 0 else { throw lastError("SSH handshake failed") }

            let fingerprint = hostFingerprint(s)
            if let known = knownFingerprint, known != fingerprint {
                throw SSHError.hostKeyChanged(expected: known, got: fingerprint)
            }

            // Duo push waits for the phone, so give auth a long timeout.
            libssh2_session_set_timeout(s, 120_000)
            answerer = answer
            authCancelled = false
            defer { answerer = nil }
            let rc = libssh2_userauth_keyboard_interactive_ex(s, user, UInt32(user.utf8.count), { name, nameLen, instr, instrLen, num, prompts, responses, abstract in
                // Servers may send rounds with no prompts (Duo's "Success. Logging you in…");
                // there is nothing to answer, so never bother the user with them.
                guard num > 0, let ctx = abstract?.pointee else { return }
                let client = Unmanaged<SSHClient>.fromOpaque(ctx).takeUnretainedValue()
                let str: (UnsafePointer<CChar>?, Int32) -> String = { p, n in
                    guard let p, n > 0 else { return "" }
                    return String(decoding: UnsafeRawBufferPointer(start: p, count: Int(n)), as: UTF8.self)
                }
                var ps: [AuthChallenge.Prompt] = []
                for i in 0..<Int(num) {
                    let p = prompts![i]
                    ps.append(.init(text: String(decoding: UnsafeRawBufferPointer(start: p.text, count: p.length), as: UTF8.self),
                                    echo: p.echo != 0))
                }
                let challenge = AuthChallenge(name: str(name, nameLen), instruction: str(instr, instrLen), prompts: ps)
                guard let answers = client.answerer?(challenge) else { client.authCancelled = true; return }
                for i in 0..<Int(num) {
                    let a = i < answers.count ? answers[i] : ""
                    responses![i].text = strdup(a)   // libssh2 frees these with free()
                    responses![i].length = UInt32(a.utf8.count)
                }
            })
            if authCancelled { throw SSHError.cancelled }
            guard rc == 0 else { throw lastError("Login failed") }

            libssh2_session_set_timeout(s, 30_000)
            libssh2_keepalive_config(s, 1, 20)
            return fingerprint
        }
    }

    /// Runs `command` in a new channel and returns its stdout.
    func exec(_ command: String) async throws -> String {
        try await run { [self] in
            guard let s = session else { throw SSHError.libssh2("Not connected") }
            guard let ch = libssh2_channel_open_ex(s, "session", 7, 2 * 1024 * 1024, 32768, nil, 0) else {
                throw lastError("Could not open a channel")
            }
            defer { libssh2_channel_free(ch) }
            guard libssh2_channel_process_startup(ch, "exec", 4, command, UInt32(command.utf8.count)) == 0 else {
                throw lastError("Command failed to start")
            }
            var out = Data()
            var buf = [CChar](repeating: 0, count: 32768)
            while true {
                let n = libssh2_channel_read_ex(ch, 0, &buf, buf.count)
                if n > 0 { buf.withUnsafeBytes { out.append(contentsOf: $0.prefix(n)) } }
                else if n == 0 { break }
                else { throw lastError("Read failed") }
            }
            // Drain stderr so the channel can close cleanly.
            while libssh2_channel_read_ex(ch, 1, &buf, buf.count) > 0 {}
            libssh2_channel_close(ch)
            libssh2_channel_wait_closed(ch)
            return String(decoding: out, as: UTF8.self)
        }
    }

    /// Sends an SSH keepalive if one is due, so idle NAT/firewall state doesn't expire.
    func keepalive() async throws {
        try await run { [self] in
            guard let s = session else { throw SSHError.libssh2("Not connected") }
            var next: Int32 = 0
            guard libssh2_keepalive_send(s, &next) == 0 else { throw lastError("Connection lost") }
        }
    }

    func close() { queue.async { [self] in closeLocked() } }

    deinit { closeLocked() }

    // MARK: - internals (SSH queue only)

    private func run<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try body() }) }
        }
    }

    private func closeLocked() {
        if let s = session {
            libssh2_session_disconnect_ex(s, 11, "bye", "")   // SSH_DISCONNECT_BY_APPLICATION
            libssh2_session_free(s)
            session = nil
        }
        if sock >= 0 { Darwin.close(sock); sock = -1 }
    }

    private func lastError(_ context: String) -> SSHError {
        guard let s = session else { return .libssh2(context) }
        var msg: UnsafeMutablePointer<CChar>?
        var len: Int32 = 0
        let code = libssh2_session_last_error(s, &msg, &len, 0)
        let detail = msg.map { String(cString: $0) } ?? "error \(code)"
        if code == -9 { return .libssh2("\(context): timed out") }   // LIBSSH2_ERROR_TIMEOUT
        return .libssh2("\(context): \(detail)")
    }

    private func hostFingerprint(_ s: OpaquePointer) -> String {
        guard let p = libssh2_hostkey_hash(s, 3) else { return "" }   // LIBSSH2_HOSTKEY_HASH_SHA256
        return Data(bytes: p, count: 32).base64EncodedString()
    }

    private static func openSocket(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, String(port), &hints, &res)
        guard rc == 0, let first = res else {
            throw SSHError.connect("Can't resolve \(host): \(String(cString: gai_strerror(rc)))")
        }
        defer { freeaddrinfo(res) }
        var ai: UnsafeMutablePointer<addrinfo>? = first
        while let a = ai {
            let fd = socket(a.pointee.ai_family, a.pointee.ai_socktype, a.pointee.ai_protocol)
            if fd >= 0 {
                var on: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &on, socklen_t(MemoryLayout<Int32>.size))
                if Darwin.connect(fd, a.pointee.ai_addr, a.pointee.ai_addrlen) == 0 { return fd }
                Darwin.close(fd)
            }
            ai = a.pointee.ai_next
        }
        throw SSHError.connect("Can't reach \(host):\(port) (\(String(cString: strerror(errno))))")
    }
}
