import Dispatch
import Foundation

#if os(macOS)
  import Darwin
#else
  import Glibc
#endif

private final class ProcessOutputBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = Data()

  func append(_ data: Data) {
    lock.lock()
    storage.append(data)
    lock.unlock()
  }

  func value() -> Data {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

extension SwiftPicoCommand {
  private static func isolateProcessGroup(_ process: Process) {
    let pid = process.processIdentifier
    guard pid > 0 else { return }
    _ = setpgid(pid, pid)
  }

  private static func signalProcessGroup(_ process: Process, signal: Int32) {
    let pid = process.processIdentifier
    guard pid > 0 else { return }
    // The child is placed in its own group immediately after launch. Signal
    // the group so shell wrappers cannot leave descendants holding a pipe or
    // continuing after the timeout.
    _ = kill(-pid, signal)
    if process.isRunning && signal == SIGTERM { process.terminate() }
  }

  static func captureProcessOutput(_ command: [String], timeout: TimeInterval? = 30) throws -> String {
    guard !command.isEmpty else {
      throw CLIError.message("cannot run an empty command")
    }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    process.standardOutput = output
    process.standardError = output
    let collected = ProcessOutputBuffer()
    output.fileHandleForReading.readabilityHandler = { handle in
      let available = handle.availableData
      guard !available.isEmpty else { return }
      collected.append(available)
    }
    try process.run()
    isolateProcessGroup(process)
    var timedOut = false
    let timeoutLock = NSLock()
    let timeoutTimer = timeout.map { limit -> DispatchSourceTimer in
      let timer = DispatchSource.makeTimerSource(queue: .global())
      timer.schedule(deadline: .now() + limit)
      timer.setEventHandler {
        guard process.isRunning else { return }
        timeoutLock.lock()
        timedOut = true
        timeoutLock.unlock()
        signalProcessGroup(process, signal: SIGTERM)
        Thread.sleep(forTimeInterval: 0.25)
        if process.isRunning { signalProcessGroup(process, signal: SIGKILL) }
      }
      timer.resume()
      return timer
    }
    process.waitUntilExit()
    timeoutTimer?.cancel()
    // The direct child may have exited while a shell-launched descendant still
    // owns the merged pipe. Close that process group before draining the final
    // bytes so capture cannot wait forever on an inherited descriptor.
    signalProcessGroup(process, signal: SIGTERM)
    signalProcessGroup(process, signal: SIGKILL)
    output.fileHandleForReading.readabilityHandler = nil
    collected.append(output.fileHandleForReading.readDataToEndOfFile())
    let text = String(decoding: collected.value(), as: UTF8.self)
    timeoutLock.lock()
    let didTimeOut = timedOut
    timeoutLock.unlock()
    if didTimeOut {
      throw CLIError.message("command timed out after \(timeout ?? 0) seconds: \(command.joined(separator: " "))\n\(text)")
    }
    guard process.terminationStatus == 0 else {
      throw CLIError.message(
        "command failed (exit \(process.terminationStatus)): \(command.joined(separator: " "))\n\(text)"
      )
    }
    return text
  }

  static func runProcess(
    _ command: [String], currentDirectory: URL? = nil, quiet: Bool = false,
    timeout: TimeInterval? = nil
  ) throws {
    guard !command.isEmpty else {
      throw CLIError.message("cannot run an empty command")
    }
    if let timeout, timeout < 0 {
      throw CLIError.message("process timeout must not be negative")
    }
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
    isolateProcessGroup(process)
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
        signalProcessGroup(process, signal: SIGTERM)
        Thread.sleep(forTimeInterval: 0.25)
        if process.isRunning {
          signalProcessGroup(process, signal: SIGKILL)
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
      throw CLIError.message(
        "command timed out after \(timeout ?? 0) seconds: \(command.joined(separator: " "))")
    }
    guard process.terminationStatus == 0 else {
      throw CLIError.message(
        "command failed (exit \(process.terminationStatus)): \(command.joined(separator: " "))")
    }
  }
}
