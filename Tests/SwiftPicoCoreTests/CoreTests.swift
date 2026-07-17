import Foundation
import Testing
@testable import SwiftPicoCore
#if os(macOS)
import Darwin
#endif

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
    #expect(throws: (any Error).self) { try SwiftPicoCommand.validateArguments(command: "build", arguments: ["--configuration"]) }
    #expect(throws: (any Error).self) { try SwiftPicoCommand.validateArguments(command: "build", arguments: ["--unknown"]) }
    #expect(throws: (any Error).self) { try SwiftPicoCommand.validateArguments(command: "dependencies", arguments: ["remove"]) }
    #expect(throws: (any Error).self) { try SwiftPicoCommand.validateArguments(command: "dependencies", arguments: ["update", "--revision", "main"]) }
}

@Test func dependencySchemaAndPathSafety() throws {
    let manifest = try JSONDecoder().decode(FirmwareDependencies.self, from: Data(#"{"schemaVersion":1,"dependencies":[]}"#.utf8))
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
    #expect(FlashStrategy.select(requestedVolume: true, bootVolume: false, serialDeviceCount: 0, picotoolAvailable: false) == .requestedVolume)
    #expect(FlashStrategy.select(requestedVolume: false, bootVolume: true, serialDeviceCount: 0, picotoolAvailable: false) == .mountedBootVolume)
    #expect(FlashStrategy.select(requestedVolume: false, bootVolume: false, serialDeviceCount: 1, picotoolAvailable: true) == .serialReset)
    #expect(FlashStrategy.select(requestedVolume: false, bootVolume: false, serialDeviceCount: 0, picotoolAvailable: true) == .picotool)
    #expect(FlashStrategy.select(requestedVolume: false, bootVolume: false, serialDeviceCount: 0, picotoolAvailable: false) == .unavailable)
}

@Test func serialMonitorSelectionAndBaudValidation() throws {
    #expect(try SerialMonitorConfiguration.selectDevice(explicit: "/dev/cu.pico", detected: []) == "/dev/cu.pico")
    #expect(try SerialMonitorConfiguration.selectDevice(explicit: nil, detected: ["/dev/cu.pico"]) == "/dev/cu.pico")
    #expect(SerialMonitorConfiguration.reconnectCandidate(explicit: nil, detected: ["/dev/cu.new"]) == "/dev/cu.new")
    #expect(SerialMonitorConfiguration.reconnectCandidate(explicit: "/dev/cu.pico", detected: ["/dev/cu.new"]) == nil)
    #expect(SerialMonitorConfiguration.reconnectCandidate(explicit: "/dev/cu.pico", detected: ["/dev/cu.pico"]) == "/dev/cu.pico")
    #expect(throws: SerialMonitorError.noDevice) {
        try SerialMonitorConfiguration.selectDevice(explicit: nil, detected: [])
    }
    #expect(throws: SerialMonitorError.multipleDevices(["/dev/cu.a", "/dev/cu.b"])) {
        try SerialMonitorConfiguration.selectDevice(explicit: nil, detected: ["/dev/cu.a", "/dev/cu.b"])
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
    let failure = StageFailure(stage: "flash", subject: "/tmp/app.uf2", recovery: "run swiftpico devices", underlying: CLIError.message("device missing"))
    let description = failure.localizedDescription
    #expect(description.contains("stage 'flash'"))
    #expect(description.contains("/tmp/app.uf2"))
    #expect(description.contains("Recovery: run swiftpico devices"))
}

@Test func flashFailureIsStageScoped() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("swiftpico-flash-test-\(UUID().uuidString)")
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
