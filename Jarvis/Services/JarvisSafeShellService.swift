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
        timeout: TimeInterval = 5
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
                    userMessage: "Failed to run \(executableURL.lastPathComponent): \(error.localizedDescription)",
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
                let success = finished.terminationStatus == 0
                continuation.resume(returning: SafeShellCommandResult(
                    success: success,
                    userMessage: success ? "Command completed." : "Command failed with exit code \(finished.terminationStatus).",
                    stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                    exitCode: finished.terminationStatus,
                    commandDescription: ([executableURL.path] + arguments).joined(separator: " ")
                ))
            }
        }
    }
}

final class JarvisSafeShellService {
    private let runner: JarvisProcessRunning

    init(runner: JarvisProcessRunning = JarvisLiveProcessRunner()) {
        self.runner = runner
    }

    func runAllowedCommand(
        _ request: SafeShellCommandRequest,
        policy: JarvisPathSafetyPolicy
    ) async -> SafeShellCommandResult {
        let command = request.command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let specification = validate(request: request, normalizedCommand: command, policy: policy) else {
            return SafeShellCommandResult(
                success: false,
                userMessage: "That shell command is not allowed.",
                stdout: "",
                stderr: "disallowed",
                exitCode: -1,
                commandDescription: request.command
            )
        }

        return await runner.run(
            executableURL: specification.executableURL,
            arguments: specification.arguments,
            currentDirectoryURL: specification.workingDirectory,
            timeout: request.timeout
        )
    }

    private func validate(
        request: SafeShellCommandRequest,
        normalizedCommand: String,
        policy: JarvisPathSafetyPolicy
    ) -> (executableURL: URL, arguments: [String], workingDirectory: URL?)? {
        let cwd = request.workingDirectory.map { URL(fileURLWithPath: $0).standardizedFileURL }
        if let cwd, !policy.canRead(path: cwd.path) {
            return nil
        }

        switch normalizedCommand {
        case "pwd":
            guard request.arguments.isEmpty else { return nil }
            return (URL(fileURLWithPath: "/bin/pwd"), [], cwd)
        case "ls":
            let allowedFlags = Set(["-l", "-a", "-la", "-al"])
            let invalidFlags = request.arguments.filter { $0.hasPrefix("-") && !allowedFlags.contains($0) }
            guard invalidFlags.isEmpty else { return nil }
            let pathArgs = request.arguments.filter { !$0.hasPrefix("-") }
            guard pathArgs.count <= 1 else { return nil }
            if let path = pathArgs.first, !policy.canRead(path: path) {
                return nil
            }
            return (URL(fileURLWithPath: "/bin/ls"), request.arguments, cwd)
        case "find":
            guard let root = request.arguments.first, policy.canRead(path: root) else { return nil }
            var sanitized: [String] = [root]
            var index = 1
            while index < request.arguments.count {
                let flag = request.arguments[index]
                switch flag {
                case "-maxdepth":
                    guard index + 1 < request.arguments.count,
                          Int(request.arguments[index + 1]) != nil else { return nil }
                    sanitized.append(flag)
                    sanitized.append(request.arguments[index + 1])
                    index += 2
                case "-name":
                    guard index + 1 < request.arguments.count else { return nil }
                    sanitized.append(flag)
                    sanitized.append(request.arguments[index + 1])
                    index += 2
                default:
                    return nil
                }
            }
            return (URL(fileURLWithPath: "/usr/bin/find"), sanitized, cwd)
        case "open":
            guard request.arguments.count == 1 else { return nil }
            let target = request.arguments[0]
            if let url = URL(string: target), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                return (URL(fileURLWithPath: "/usr/bin/open"), [target], cwd)
            }
            guard policy.canRead(path: target) else { return nil }
            return (URL(fileURLWithPath: "/usr/bin/open"), [target], cwd)
        case "git":
            guard let subcommand = request.arguments.first?.lowercased(), subcommand == "status" else { return nil }
            let tail = Array(request.arguments.dropFirst())
            let allowedFlags = Set(["--short", "--branch"])
            guard tail.allSatisfy({ allowedFlags.contains($0) }) else { return nil }
            return (URL(fileURLWithPath: "/usr/bin/git"), request.arguments, cwd)
        default:
            return nil
        }
    }
}
