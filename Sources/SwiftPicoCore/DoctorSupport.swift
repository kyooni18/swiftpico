import Dispatch
import Foundation

#if os(macOS)
  import Darwin
#else
  import Glibc
#endif

extension SwiftPicoCommand {
  static func list() {
    let manager = FileManager.default
    let volumes =
      manager.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: []) ?? []
    let bootVolumes = volumes.filter {
      isPicoBootVolume($0)
    }
    print("=== Pico Boot Volumes ===")
    print(
      bootVolumes.isEmpty
        ? "  none (hold BOOTSEL to enter boot mode)"
        : bootVolumes.map { "  \($0.path)" }.joined(separator: "\n"))

    print("\n=== Serial Devices ===")
    let devices = serialDevices()
    print(devices.isEmpty ? "  none" : devices.map { "  \($0)" }.joined(separator: "\n"))
  }

  // MARK: - environment diagnostics

  static func doctor(_ arguments: [String]) throws {
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let detectedSerialDevices = serialDevices()
    let hasExplicitContext = option("--context", in: arguments) != nil
    let hasDiscoveredContext = findContext(from: current) != nil
    let project = (hasExplicitContext || hasDiscoveredContext) ? try context(arguments) : nil
    let picoKitRoot =
      project.flatMap { try? resolvePicoKitRoot(project: $0, config: $0.config) }
      ?? findPicoKitRoot(from: current)
    print("=== PicoKit Environment ===")
    reportTool("swift", arguments: ["--version"])
    reportTool(cmakeExecutable(), arguments: ["--version"])
    reportTool(ninjaExecutable(), arguments: ["--version"])
    reportTool("arm-none-eabi-gcc", arguments: ["--version"])
    if let picoKitRoot {
      let sdk = try? sharedPicoSDK(for: picoKitRoot)
      let bridge = picoKitRoot.appendingPathComponent("Firmware/PicoKitSDKBridge.c")
      print("  PicoKit:     \(picoKitRoot.path)")
      print("  Pico SDK:    \(sdk?.path ?? "MISSING (run swiftpico build)")")
      print(
        "  SDK bridge:  \(FileManager.default.fileExists(atPath: bridge.path) ? "available" : "MISSING")"
      )
    } else {
      print("  PicoKit:     not found from \(current.path)")
    }
    if let project {
      let lock = project.root.appendingPathComponent(DependencySupport.lockPath)
      let generated = project.root.appendingPathComponent(DependencySupport.generatedPath)
      let state = project.root.appendingPathComponent(".swiftpico/firmware-build.json")
      let legacyPicoKitRoot = picoKitRoot == project.root && project.config.schemaVersion == nil
      print("  Project:     \(project.root.path) (schema \(project.config.schemaVersion ?? 0))")
      print("  Lock file:   \(legacyPicoKitRoot ? "not applicable (legacy PicoKit checkout)" : (FileManager.default.fileExists(atPath: lock.path) ? "available" : "MISSING (run swiftpico dependencies resolve)"))")
      print("  CMake state: \(legacyPicoKitRoot ? "not applicable (legacy PicoKit checkout)" : (FileManager.default.fileExists(atPath: generated.path) ? "generated" : "MISSING (run swiftpico dependencies generate)"))")
      print(
        "  Build state: \(FileManager.default.fileExists(atPath: state.path) ? "recorded" : "not built")"
      )
    } else {
      print("  Project:     not found (project-specific checks skipped)")
    }
    print("  Boot volumes: \(findBootVolume()?.path ?? "none")")
    print(
      "  Serial:      \(detectedSerialDevices.joined(separator: ", ").isEmpty ? "none" : detectedSerialDevices.joined(separator: ", "))"
    )
    try reportCallbackProbe()
  }

  static func reportCallbackProbe() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(
      "swiftpico-callback-probe-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let header = root.appendingPathComponent("Callbacks.h")
    let caller = root.appendingPathComponent("Caller.c")
    let swift = root.appendingPathComponent("Callback.swift")
    try """
    #pragma once
    #include <stdint.h>
    int32_t swiftpico_callback_probe(uint32_t value);
    """.write(to: header, atomically: true, encoding: .utf8)
    try """
    #include "Callbacks.h"
    int32_t call_swiftpico_callback_probe(void) { return swiftpico_callback_probe(42); }
    """.write(to: caller, atomically: true, encoding: .utf8)
    try """
    @_cdecl("swiftpico_callback_probe")
    public func callbackProbe(_ value: UInt32) -> Int32 { Int32(bitPattern: value) }
    """.write(to: swift, atomically: true, encoding: .utf8)

    guard let compiler = swiftCompilerPath() else {
      throw CLIError.message("callback probe failed: real swiftc toolchain binary was not found")
    }
    let swiftObject = root.appendingPathComponent("Callback.o")
    let callerObject = root.appendingPathComponent("Caller.o")
    let linkedObject = root.appendingPathComponent("Linked.o")
    do {
      try runProcess(
        [
          compiler, "-target", "armv6m-none-none-eabi",
          "-enable-experimental-feature", "Embedded", "-wmo",
          "-parse-as-library", "-c", swift.path, "-o", swiftObject.path,
        ], quiet: true)
      try runProcess(
        [
          "arm-none-eabi-gcc", "-mcpu=cortex-m0plus", "-mthumb",
          "-I", root.path, "-c", caller.path, "-o", callerObject.path,
        ], quiet: true)
      try runProcess(
        [
          "arm-none-eabi-ld", "-r", swiftObject.path, callerObject.path,
          "-o", linkedObject.path,
        ], quiet: true)
      let symbols = try captureProcessOutput(["arm-none-eabi-nm", linkedObject.path])
      guard symbols.contains(" T swiftpico_callback_probe") else {
        throw CLIError.message("exported callback symbol was not present")
      }
      print("  C callback:  supported (compiled Swift export and C caller)")
    } catch {
      print("  C callback:  FAILED")
      throw CLIError.message("C-to-Swift callback probe failed: \(error.localizedDescription)")
    }
  }

  static func reportTool(_ executable: String, arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      let firstLine =
        String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .split(separator: "\n").first.map(String.init) ?? ""
      print("  \(executable): \(process.terminationStatus == 0 ? firstLine : "MISSING")")
    } catch {
      print("  \(executable): MISSING")
    }
  }

}
