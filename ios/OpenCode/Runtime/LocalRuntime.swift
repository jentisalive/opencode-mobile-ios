import Foundation
import Combine

@MainActor final class LocalRuntime: ObservableObject {
    @Published var status = "Stopped"
    @Published var running = false
    @Published var log = ""
    private var pid: pid_t = 0
    private var generation = UUID()
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let workspace = documents.appendingPathComponent("Projects", isDirectory: true)
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenCode", isDirectory: true)
    var logURL: URL { Self.support.appendingPathComponent("runtime.log") }

    func start(password: String) throws {
        guard pid == 0 else {
            guard status != "Stopping…" else { throw APIError(message: "The engine is still stopping. Wait a moment, then start it again.") }
            return
        }
        #if targetEnvironment(simulator)
        throw APIError(message: "The local engine requires a physical iPhone with TrollStore. The simulator can test the interface and API only.")
        #else
        let fm = FileManager.default
        for folder in [Self.support, Self.workspace, Self.support.appendingPathComponent("tmp"), Self.support.appendingPathComponent("memory")] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let runtime = Bundle.main.bundleURL.appendingPathComponent("NativeRuntime")
        let node = runtime.appendingPathComponent("node")
        let server = runtime.appendingPathComponent("server.mjs")
        guard fm.isExecutableFile(atPath: node.path), fm.fileExists(atPath: server.path) else {
            throw APIError(message: "This build does not contain the native runtime. Install the complete TrollStore IPA from the iOS build artifacts.")
        }
        var env = ProcessInfo.processInfo.environment
        let customPrefix = UserDefaults.standard.string(forKey: "bootstrapPrefix") ?? "/var/jb"
        env["HOME"] = Self.support.path
        env["XDG_CONFIG_HOME"] = Self.support.appendingPathComponent("config").path
        env["XDG_DATA_HOME"] = Self.support.appendingPathComponent("data").path
        env["XDG_CACHE_HOME"] = Self.support.appendingPathComponent("cache").path
        env["XDG_STATE_HOME"] = Self.support.appendingPathComponent("state").path
        env["TMPDIR"] = Self.support.appendingPathComponent("tmp").path
        env["PATH"] = "\(runtime.path)/bin:\(customPrefix)/bin:\(customPrefix)/usr/bin:/usr/bin:/bin"
        for shell in [customPrefix + "/bin/bash", customPrefix + "/bin/sh", customPrefix + "/usr/bin/sh", "/bin/sh"] where fm.isExecutableFile(atPath: shell) {
            env["SHELL"] = shell; break
        }
        env["OPENCODE_SERVER_PASSWORD"] = password
        env["OPENCODE_PORT"] = "4096"
        env["OPENCODE_WORKSPACE"] = Self.workspace.path
        env["OPENCODE_DISABLE_AUTOUPDATE"] = "true"
        env["OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER"] = "true"
        let args = [node.path, "--single-threaded", "--experimental-sqlite", "--no-warnings", "--max-old-space-size=768", server.path]
        var cArgs = args.map { strdup($0) } + [nil]
        var cEnv = env.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { cArgs.forEach { free($0) }; cEnv.forEach { free($0) } }
        let error = oc_spawn(node.path, &cArgs, &cEnv, logURL.path, &pid)
        guard error == 0 else { pid = 0; throw APIError(message: "Cannot launch native engine: \(String(cString: strerror(error))). This installation may not permit subprocesses.") }
        generation = UUID()
        let current = generation
        let child = pid
        status = "Starting local engine…"
        Task { [weak self] in
            let code = await Task.detached(priority: .utility) { oc_wait(child) }.value
            guard let self, self.generation == current else { return }
            self.pid = 0; self.running = false
            self.status = code == 0 ? "Stopped" : "Engine exited (\(code))"
            self.readLog()
        }
        #endif
    }
    func markReady() { running = true; status = "On this iPhone" }
    func stop() {
        guard pid > 0 else { running = false; status = "Stopped"; return }
        oc_stop(pid); running = false; status = "Stopping…"
        let child = pid
        let current = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.generation == current, self.pid == child else { return }
            oc_force_stop(child)
        }
    }
    func readLog() {
        do {
            let file = try FileHandle(forReadingFrom: logURL)
            defer { try? file.close() }
            let end = try file.seekToEnd()
            try file.seek(toOffset: end > 24000 ? end - 24000 : 0)
            log = String(decoding: try file.read(upToCount: 24000) ?? Data(), as: UTF8.self)
        } catch { log = "No runtime log yet." }
    }
}
