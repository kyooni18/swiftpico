import Foundation
import Testing

@testable import SwiftPicoCore

#if os(macOS)
  import Darwin
#endif

@Test func serialTemplatesRespectMonitorConnectionState() {
  let serial = SwiftPicoCommand.templateSource(template: "serial", board: "pico", name: "Echo")
  #expect(serial.contains("if !Serial.connected"))
  #expect(serial.contains("Serial echo ready"))

  let blink = SwiftPicoCommand.templateSource(template: "blink", board: "pico2_w", name: "Blink")
  #expect(blink.contains("Serial.connected && !announced"))

  let adc = SwiftPicoCommand.templateSource(template: "adc", board: "pico", name: "ADC")
  #expect(adc.contains("if Serial.connected"))
}

@Test func configurationSchemas() throws {
  let legacy = try JSONDecoder().decode(PicoKitConfig.self, from: Data(#"{"board":"pico"}"#.utf8))
  #expect(try ProjectSchemaMigration.required(for: legacy.schemaVersion) == .legacyV0)
  #expect(legacy.configuration == "release")
  #expect(legacy.openOCD == "openocd")
  #expect(legacy.openOCDConfig.isEmpty)
  let current = try JSONEncoder().encode(PicoKitConfig(board: "pico"))
  #expect(String(decoding: current, as: UTF8.self).contains("schemaVersion"))
  #expect(throws: (any Error).self) { try ProjectSchemaMigration.required(for: 99) }
}

@Test func argumentValidation() throws {
  try SwiftPicoCommand.validateArguments(command: "build", arguments: ["--configuration", "debug"])
  #expect(throws: (any Error).self) {
    try SwiftPicoCommand.validateArguments(command: "build", arguments: ["--configuration"])
  }
  #expect(throws: (any Error).self) {
    try SwiftPicoCommand.validateArguments(command: "build", arguments: ["--unknown"])
  }
  #expect(throws: (any Error).self) {
    try SwiftPicoCommand.validateArguments(command: "dependencies", arguments: ["remove"])
  }
  #expect(throws: (any Error).self) {
    try SwiftPicoCommand.validateArguments(
      command: "dependencies", arguments: ["update", "--revision", "main"])
  }
}

@Test func projectNameValidationRejectsPathLikeNames() {
  for name in ["", "   ", ".", "..", "../escape", "nested/project", "nested\\project", "line\nfeed"] {
    #expect(throws: (any Error).self) {
      try SwiftPicoCommand.initialise(["--name", name, "--skip-resolve"])
    }
  }
  do {
    try SwiftPicoCommand.initialise(["--name", "line\nfeed", "--skip-resolve"])
    Issue.record("a control-character project name unexpectedly succeeded")
  } catch {
    #expect(error.localizedDescription.contains("\\n"))
    #expect(!error.localizedDescription.contains("line\nfeed"))
  }
}

@Test func emptyProcessCommandsReportErrors() {
  #expect(throws: (any Error).self) {
    try SwiftPicoCommand.captureProcessOutput([])
  }
  #expect(throws: (any Error).self) {
    try SwiftPicoCommand.runProcess([])
  }
  #expect(throws: (any Error).self) {
    try SwiftPicoCommand.runProcess(["true"], timeout: -1)
  }
}

@Test func processOutputIncludesDiagnosticsFromBothStreams() throws {
  let output = try SwiftPicoCommand.captureProcessOutput(
    ["sh", "-c", "printf 'stdout'; printf 'stderr' >&2"])
  #expect(output.contains("stdout"))
  #expect(output.contains("stderr"))

  do {
    _ = try SwiftPicoCommand.captureProcessOutput(
      ["sh", "-c", "printf 'failure-detail' >&2; exit 7"])
    Issue.record("a failing command unexpectedly succeeded")
  } catch {
    #expect(error.localizedDescription.contains("exit 7"))
    #expect(error.localizedDescription.contains("failure-detail"))
  }
}

@Test func processTimeoutTerminatesHangingCommand() {
  do {
    try SwiftPicoCommand.runProcess(["sh", "-c", "sleep 2"], quiet: true, timeout: 0.05)
    Issue.record("a hanging command unexpectedly completed")
  } catch {
    #expect(error.localizedDescription.contains("timed out after 0.05 seconds"))
  }
}

@Test func dependencySchemaAndPathSafety() throws {
  let manifest = try JSONDecoder().decode(
    FirmwareDependencies.self, from: Data(#"{"schemaVersion":1,"dependencies":[]}"#.utf8))
  #expect(manifest.schemaVersion == SwiftPicoVersion.dependencySchema)
  #expect(PathSafety.isSafeDependencyPath("src/driver.c"))
  #expect(!PathSafety.isSafeDependencyPath("../secret"))
  #expect(!PathSafety.isSafeDependencyPath("/tmp/secret"))
}

@Test func buildStateInvalidation() {
  let expected = BuildStateFingerprint(swiftPicoVersion: "1", picoKitVersion: "2")
  #expect(expected.invalidates(expected) == false)
  #expect(expected.invalidates(.init(swiftPicoVersion: "0", picoKitVersion: "2")) == true)
  #expect(expected.invalidates(.init(swiftPicoVersion: "1", picoKitVersion: "1")) == true)
}

@Test func flashStrategySelection() {
  #expect(
    FlashStrategy.select(
      requestedVolume: true, bootVolume: false, serialDeviceCount: 0, picotoolAvailable: false)
      == .requestedVolume)
  #expect(
    FlashStrategy.select(
      requestedVolume: false, bootVolume: true, serialDeviceCount: 0, picotoolAvailable: false)
      == .mountedBootVolume)
  #expect(
    FlashStrategy.select(
      requestedVolume: false, bootVolume: false, serialDeviceCount: 1, picotoolAvailable: true)
      == .serialReset)
  #expect(
    FlashStrategy.select(
      requestedVolume: false, bootVolume: false, serialDeviceCount: 0, picotoolAvailable: true)
      == .picotool)
  #expect(
    FlashStrategy.select(
      requestedVolume: false, bootVolume: false, serialDeviceCount: 0, picotoolAvailable: false)
      == .unavailable)
}

@Test func serialMonitorSelectionAndBaudValidation() throws {
  #expect(
    try SerialMonitorConfiguration.selectDevice(explicit: "/dev/cu.pico", detected: [])
      == "/dev/cu.pico")
  #expect(
    try SerialMonitorConfiguration.selectDevice(explicit: nil, detected: ["/dev/cu.pico"])
      == "/dev/cu.pico")
  #expect(
    SerialMonitorConfiguration.reconnectCandidate(explicit: nil, detected: ["/dev/cu.new"])
      == "/dev/cu.new")
  #expect(
    SerialMonitorConfiguration.reconnectCandidate(
      explicit: "/dev/cu.pico", detected: ["/dev/cu.new"]) == nil)
  #expect(
    SerialMonitorConfiguration.reconnectCandidate(
      explicit: "/dev/cu.pico", detected: ["/dev/cu.pico"]) == "/dev/cu.pico")
  #expect(throws: SerialMonitorError.noDevice) {
    try SerialMonitorConfiguration.selectDevice(explicit: nil, detected: [])
  }
  #expect(throws: SerialMonitorError.multipleDevices(["/dev/cu.a", "/dev/cu.b"])) {
    try SerialMonitorConfiguration.selectDevice(
      explicit: nil, detected: ["/dev/cu.a", "/dev/cu.b"])
  }
  #expect(try SerialMonitorConfiguration.baud(from: "115200") == 115200)
  #expect(throws: SerialMonitorError.invalidBaud("0")) {
    try SerialMonitorConfiguration.baud(from: "0")
  }
  #expect(throws: SerialMonitorError.invalidBaud("5000000")) {
    try SerialMonitorConfiguration.baud(from: "5000000")
  }
}

#if os(macOS)
  @Test func serialConnectionPreservesFullDuplexBytes() throws {
    let master = posix_openpt(O_RDWR | O_NOCTTY | O_NONBLOCK)
    #expect(master >= 0)
    guard master >= 0 else { return }
    defer { _ = Darwin.close(master) }
    #expect(grantpt(master) == 0)
    #expect(unlockpt(master) == 0)
    guard let slavePointer = ptsname(master) else {
      Issue.record("PTY slave path was unavailable")
      return
    }

    // A PTY has no DTR modem-control line. Opening it proves the monitor keeps
    // byte-stream devices usable while asserting DTR on real USB CDC devices.
    let connection = SerialConnection()
    try connection.open(String(cString: slavePointer), baud: speed_t(115200))
    defer { connection.close() }

    let inbound = Data([0x00, 0x0A, 0x0D, 0xFF])
    inbound.withUnsafeBytes { bytes in
      _ = Darwin.write(master, bytes.baseAddress, bytes.count)
    }
    #expect(connection.read() == inbound)

    let outbound = Data([0x7F, 0x0A, 0x00, 0xC3])
    #expect(connection.write(outbound))
    var received = [UInt8](repeating: 0, count: outbound.count)
    let count = received.withUnsafeMutableBytes { bytes in
      Darwin.read(master, bytes.baseAddress, bytes.count)
    }
    #expect(count == outbound.count)
    #expect(Data(received) == outbound)
  }

  @Test func reconnectMonitorRetainsInputAfterWriteFailure() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let sourceURL = packageRoot.appendingPathComponent("Sources/SwiftPicoCore/MonitorCommands.swift")
    let source = try String(contentsOfFile: sourceURL.path, encoding: .utf8)
    #expect(source.contains("while offset < data.count && !connection.write(data, offset: &offset)"))
    #expect(source.contains("Preserve bytes typed during a CDC reset"))
    #expect(source.contains("arguments.contains(\"--reconnect\")"))
    #expect(source.contains("connection.write(data, offset: &offset)"))
    let readme = try String(
      contentsOfFile: packageRoot.appendingPathComponent("README.md").path, encoding: .utf8)
    #expect(readme.contains("retries bytes typed while the replacement device is coming back"))
  }

  @Test func flashDiagnosticsIncludeDetectedSerialPath() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let sourceURL = packageRoot.appendingPathComponent("Sources/SwiftPicoCore/FlashSupport.swift")
    let source = try String(contentsOfFile: sourceURL.path, encoding: .utf8)
    #expect(source.contains("USB serial reset also failed for \\(detectedSerialDevices[0])"))
    #expect(!source.contains("USB serial reset also failed for (detectedSerialDevices[0])"))
    #expect(source.contains("requestedPicotool == nil && detectedSerialDevices.count == 1"))
    #expect(source.contains("USB serial reset was not attempted because --picotool was supplied"))
  }

  @Test func serialTrafficStatsAreThreadSafeCounters() {
    let stats = SerialTrafficStats()
    stats.recordSent(11)
    stats.recordSent(4)
    stats.recordReceived(7)
    #expect(stats.sent == 15)
    #expect(stats.received == 7)
  }
#endif

@Test func stageFailureIncludesRecoveryContext() {
  let failure = StageFailure(
    stage: "flash", subject: "/tmp/app.uf2", recovery: "run swiftpico devices",
    underlying: CLIError.message("device missing"))
  let description = failure.localizedDescription
  #expect(description.contains("stage 'flash'"))
  #expect(description.contains("/tmp/app.uf2"))
  #expect(description.contains("Recovery: run swiftpico devices"))
}

@Test func flashFailureIsStageScoped() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "swiftpico-flash-test-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let config = PicoKitConfig(board: "pico", uf2: "Firmware/build/missing.uf2")
  try JSONEncoder.pretty.encode(config).write(to: root.appendingPathComponent("swiftpico.json"))

  do {
    try SwiftPicoCommand.flash(["--context", root.appendingPathComponent("swiftpico.json").path])
    Issue.record("Expected flash to fail for a missing UF2")
  } catch {
    let description = error.localizedDescription
    #expect(description.contains("stage 'flash'"))
    #expect(description.contains("missing.uf2"))
    #expect(description.contains("swiftpico devices"))
  }
}
