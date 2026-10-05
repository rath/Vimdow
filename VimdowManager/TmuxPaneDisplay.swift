import Foundation
import Darwin

struct TmuxClient: Equatable, Sendable {
    let pid: Int32
    let tty: String
    let pane: String
    let focused: Bool

    static let format = "#{client_pid}\t#{client_tty}\t#{pane_id}\t#{client_flags}\t#{client_termfeatures}"

    static func parse(_ output: String) -> [Self] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 5, let pid = Int32(fields[0]), pid > 1,
                  fields[1].hasPrefix("/dev/"), fields[2].hasPrefix("%"),
                  Int(fields[2].dropFirst()) != nil else { return nil }
            let flags = Set(fields[3].split(separator: ","))
            let features = Set(fields[4].split(separator: ","))
            return Self(pid: pid, tty: String(fields[1]), pane: String(fields[2]),
                        focused: flags.contains("attached") && flags.contains("focused") && features.contains("focus"))
        }
    }

    static func select(from clients: [Self], terminalPID: Int32, parents: [Int32: Int32]) -> Self? {
        let matches = clients.filter { client in
            guard client.focused else { return false }
            var pid = client.pid
            var visited: Set<Int32> = []
            while pid > 1, visited.insert(pid).inserted {
                if pid == terminalPID { return true }
                guard let parent = parents[pid] else { return false }
                pid = parent
            }
            return false
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

struct TmuxPaneTarget: Equatable, Sendable {
    let executable: String
    let client: TmuxClient
    let targetsPane: Bool

    var arguments: [String] {
        // Older tmux blocks its command client until selection unless -b is used.
        targetsPane ? ["display-panes", "-t", client.pane] : ["display-panes", "-b", "-t", client.tty]
    }
}

/// Best-effort local integration. Never injects text or keys into a shell.
@MainActor
final class TmuxPaneDisplay {
    var isEnabled = false {
        didSet { if !isEnabled { cancel() } }
    }
    private var task: Task<Void, Never>?
    private let resolve: @Sendable (Int32) async -> TmuxPaneTarget?
    private let display: @Sendable (TmuxPaneTarget) async -> Void
    private let delay: Duration

    init(delay: Duration = .milliseconds(150),
         resolve: @escaping @Sendable (Int32) async -> TmuxPaneTarget? = TmuxLocalCommand.resolve,
         display: @escaping @Sendable (TmuxPaneTarget) async -> Void = TmuxLocalCommand.display) {
        self.delay = delay
        self.resolve = resolve
        self.display = display
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func show(terminalPID: Int32, isStillFocused: @escaping @MainActor () -> Bool) {
        cancel()
        guard isEnabled else { return }
        task = Task { [delay, resolve, display] in
            // Let the terminal deliver its focus event to tmux before selecting a client.
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, isStillFocused(),
                  let target = await resolve(terminalPID),
                  !Task.isCancelled, isStillFocused() else { return }
            await display(target)
        }
    }

    deinit { task?.cancel() }
}

enum TmuxLocalCommand {
    static func resolve(terminalPID: Int32) async -> TmuxPaneTarget? {
        await Task.detached(priority: .userInitiated) {
            let paths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]
                + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/tmux" }
            guard let executable = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
                  run(executable, ["show-options", "-s", "-v", "focus-events"])?.trimmingCharacters(in: .whitespacesAndNewlines) == "on",
                  let commands = run(executable, ["list-commands"]),
                  let syntax = commands.split(separator: "\n").first(where: { $0.hasPrefix("display-panes ") }),
                  syntax.contains("target-pane") || syntax.contains("target-client"),
                  let processes = run("/bin/ps", ["-axo", "pid=,ppid="]),
                  let output = run(executable, ["list-clients", "-F", TmuxClient.format]) else { return nil }
            var parents: [Int32: Int32] = [:]
            for line in processes.split(separator: "\n") {
                let fields = line.split(whereSeparator: \.isWhitespace)
                if fields.count == 2, let pid = Int32(fields[0]), let parent = Int32(fields[1]) { parents[pid] = parent }
            }
            guard let client = TmuxClient.select(from: TmuxClient.parse(output), terminalPID: terminalPID, parents: parents) else {
                return nil
            }
            return TmuxPaneTarget(executable: executable, client: client, targetsPane: syntax.contains("target-pane"))
        }.value
    }

    static func display(_ target: TmuxPaneTarget) async {
        let worker = Task.detached(priority: .userInitiated) {
            // Recheck the client after discovery; switching tabs can change the active pane.
            guard !Task.isCancelled,
                  let output = run(target.executable, ["list-clients", "-F", TmuxClient.format]),
                  TmuxClient.parse(output).contains(target.client), !Task.isCancelled else { return }
            _ = run(target.executable, target.arguments)
        }
        await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Runs outside the main actor. Bound failures so absent/unresponsive tmux cannot stall switching.
    static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Resolve the default local socket, even if Vimdow was launched from inside tmux.
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TMUX")
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(750), execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
