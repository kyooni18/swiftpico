import Foundation
import Dispatch
#if os(macOS)
import Darwin
#else
import Glibc
#endif

extension SwiftPicoCommand {
    static func captureProcessOutput(_ command: [String]) throws -> String {
        precondition(!command.isEmpty)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.standardOutput = output
        // A process can fill either pipe before it exits. Merging them keeps
        // diagnostics available without risking a waitUntilExit deadlock.
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw CLIError.message("command failed (exit \(process.terminationStatus)): \(command.joined(separator: " "))\n\(text)")
        }
        return text
    }

    static func runProcess(_ command: [String], currentDirectory: URL? = nil, quiet: Bool = false, timeout: TimeInterval? = nil) throws {
        precondition(!command.isEmpty)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = currentDirectory
        if !quiet {
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        var timedOut = false
        let timeoutLock = NSLock()
        let timeoutTimer: DispatchSourceTimer?
        if let timeout {
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                guard process.isRunning else { return }
                timeoutLock.lock()
                timedOut = true
                timeoutLock.unlock()
                process.terminate()
                Thread.sleep(forTimeInterval: 0.25)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            timer.resume()
            timeoutTimer = timer
        } else {
            timeoutTimer = nil
        }
        process.waitUntilExit()
        timeoutTimer?.cancel()
        timeoutLock.lock()
        let didTimeOut = timedOut
        timeoutLock.unlock()
        if didTimeOut {
            throw CLIError.message("command timed out after \(Int(timeout ?? 0)) seconds: \(command.joined(separator: " "))")
        }
        guard process.terminationStatus == 0 else { throw CLIError.message("command failed (exit \(process.terminationStatus)): \(command.joined(separator: " "))") }
    }
}
