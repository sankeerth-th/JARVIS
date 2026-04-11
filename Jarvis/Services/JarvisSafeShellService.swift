import Foundation

struct SafeShellCommandRequest: Equatable {
    var command: String
    var arguments: [String]
    var workingDirectory: String?
    var timeout: TimeInterval

    init(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        timeout: TimeInterval = 20
    ) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }
}

struct SafeShellCommandResult: Equatable {
    let success: Bool
    let userMessage: String
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let commandDescription: String
}

enum JarvisTerminalRisk: String, Equatable {
    case benign
    case requiresApproval
    case catastrophic
}

struct JarvisTerminalAssessment: Equatable {
    let risk: JarvisTerminalRisk
    let reason: String
}

protocol JarvisProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeout: TimeInterval
    ) async -> SafeShellCommandResult
}

struct JarvisLiveProcessRunner: JarvisProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeout: TimeInterval
    ) async -> SafeShellCommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: SafeShellCommandResult(
                    success: false,
                    userMessage: "Failed to run command: \(error.localizedDescription)",
                    stdout: "",
                    stderr: error.localizedDescription,
                    exitCode: -1,
                    commandDescription: ([executableURL.path] + arguments).joined(separator: " ")
                ))
                return
            }

            let timeoutTask = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + max(timeout, 1), execute: timeoutTask)

            process.terminationHandler = { finished in
                timeoutTask.cancel()
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let status = finished.terminationStatus
                continuation.resume(returning: SafeShellCommandResult(
                    success: status == 0,
                    userMessage: status == 0 ? "Command completed." : "Command failed with exit code \(status).",
                    stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                    exitCode: status,
                    commandDescription: ([executableURL.path] + arguments).joined(separator: " ")
                ))
            }
        }
    }
}

final class JarvisTerminalExecutionService {
    private let runner: JarvisProcessRunning

    init(runner: JarvisProcessRunning = JarvisLiveProcessRunner()) {
        self.runner = runner
    }

    func assess(_ request: SafeShellCommandRequest, policy: JarvisPathSafetyPolicy) -> JarvisTerminalAssessment {
        let rendered = render(request).lowercased()
        let catastrophicPatterns = [
            "rm -rf /", "rm -rf ~", "sudo ", "dd if=", "diskutil erase", "mkfs", "shutdown -h", "reboot", ":(){:|:&};:",
            "chmod -r 777 /", "chown -r", "git clean -fdx", "git reset --hard", "killall finder", "osascript -e 'tell app"
        ]
        if catastrophicPatterns.contains(where: rendered.contains) {
            return .init(risk: .catastrophic, reason: "Command matches a catastrophic pattern.")
        }

        let writePatterns = [">", ">>", "mv ", "cp ", "rm ", "mkdir ", "rmdir ", "touch ", "sed -i", "perl -pi", "tee "]
        if writePatterns.contains(where: rendered.contains) {
            return .init(risk: .requiresApproval, reason: "Command modifies files or system state.")
        }

        if let cwd = request.workingDirectory, !policy.canRead(path: cwd) {
            return .init(risk: .catastrophic, reason: "Working directory is outside the approved read scope.")
        }

        return .init(risk: .benign, reason: "Inspection-style command.")
    }

    func runCommand(
        _ request: SafeShellCommandRequest,
        policy: JarvisPathSafetyPolicy
    ) async -> SafeShellCommandResult {
        let cwd = request.workingDirectory.map { URL(fileURLWithPath: $0).standardizedFileURL }
        if let cwd, !policy.canRead(path: cwd.path) {
            return SafeShellCommandResult(
                success: false,
                userMessage: "Working directory is not readable under the current host policy.",
                stdout: "",
                stderr: "disallowed cwd",
                exitCode: -1,
                commandDescription: render(request)
            )
        }

        return await runner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", render(request)],
            currentDirectoryURL: cwd,
            timeout: request.timeout
        )
    }

    private func render(_ request: SafeShellCommandRequest) -> String {
        ([request.command] + request.arguments).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class JarvisSafeShellService {
    private let terminal: JarvisTerminalExecutionService

    init(runner: JarvisProcessRunning = JarvisLiveProcessRunner()) {
        self.terminal = JarvisTerminalExecutionService(runner: runner)
    }

    func assess(_ request: SafeShellCommandRequest, policy: JarvisPathSafetyPolicy) -> JarvisTerminalAssessment {
        terminal.assess(request, policy: policy)
    }

    func runAllowedCommand(
        _ request: SafeShellCommandRequest,
        policy: JarvisPathSafetyPolicy
    ) async -> SafeShellCommandResult {
        let assessment = terminal.assess(request, policy: policy)
        guard assessment.risk == .benign else {
            return SafeShellCommandResult(
                success: false,
                userMessage: assessment.reason,
                stdout: "",
                stderr: assessment.risk.rawValue,
                exitCode: -1,
                commandDescription: ([request.command] + request.arguments).joined(separator: " ")
            )
        }

        return await terminal.runCommand(request, policy: policy)
    }
}
