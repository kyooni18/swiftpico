import Dispatch
import Foundation

#if os(macOS)
  import Darwin
#else
  import Glibc
#endif

extension SwiftPicoCommand {
  static func flash(_ arguments: [String]) throws {
    do {
      try flashImpl(arguments)
    } catch let failure as StageFailure {
      throw failure
    } catch {
      let subject = option("--uf2", in: arguments) ?? "the configured UF2 image"
      throw StageFailure(
        stage: "flash",
        subject: subject,
        recovery:
          "run 'swiftpico devices'; reconnect the board in BOOTSEL mode, or pass --volume <boot-volume>",
        underlying: error
      )
    }
  }

  private static func flashImpl(_ arguments: [String]) throws {
    let project = try context(arguments)
    let config = project.config
    let uf2 = option("--uf2", in: arguments) ?? config.uf2
    guard let uf2 else {
      throw CLIError.message("set 'uf2' in swiftpico.json or pass --uf2 path/to/app.uf2")
    }
    let source = project.url(for: uf2)
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw CLIError.message("UF2 file not found: \(source.path)")
    }

    if let requestedVolume = option("--volume", in: arguments).map({ project.url(for: $0) }) {
      try copyUF2ToVolume(source, volume: requestedVolume)
      print("Flashed \(source.lastPathComponent) to \(requestedVolume.path)")
      try waitForApplication(config, bootVolume: requestedVolume)
      return
    }

    let requestedPicotool = option("--picotool", in: arguments).map { project.url(for: $0).path }
    let picotool = requestedPicotool ?? findPicotool(config, projectRoot: project.root)

    // Resolve the board's current state before asking either USB stack to
    // transition it. This avoids a second reset while Disk Arbitration is
    // still publishing an already-mounted BOOTSEL device.
    if let bootVolume = findBootVolume() {
      try flashBootloader(source, volume: bootVolume, picotool: picotool)
      try waitForApplication(config, bootVolume: bootVolume)
      return
    }

    // The Pico SDK's CDC reset is independent of picotool's forced-reset
    // serial tracking. Prefer it for the ordinary one-board workflow.
    if requestedPicotool == nil, serialDevices().count == 1 {
      print("Requesting BOOTSEL over USB serial…")
      do {
        try resetToBootloaderOverUSB()
        if let bootVolume = waitForBootVolume() {
          try flashBootloader(source, volume: bootVolume, picotool: picotool)
          try waitForApplication(config, bootVolume: bootVolume)
          return
        }
        print("USB serial reset did not mount a BOOTSEL volume; trying picotool…")
      } catch {
        print("USB serial reset failed (\(error.localizedDescription)); trying picotool…")
      }
    }

    var picotoolFailed = false
    if let picotool {
      print("Flashing \(source.lastPathComponent) over USB with picotool…")
      do {
        // This is the fallback for a board picotool can see but whose
        // BOOTSEL volume was not published. Keep BOOTSEL accessible
        // until the verified load is complete, then reboot explicitly.
        try runProcess([picotool, "load", "-F", "-v", source.path])
        try runProcess([picotool, "reboot", "--application"])
        try waitForApplication(config)
        print("Flashed \(source.lastPathComponent) over USB.")
        return
      } catch {
        picotoolFailed = true
        print("picotool could not enter BOOTSEL; falling back to USB serial reset…")
      }
    }

    let picotoolReason =
      picotoolFailed
      ? "picotool could not access an RP-series device"
      : "picotool was not found"
    throw CLIError.message(
      "\(picotoolReason), and no single USB serial device is available for the automatic BOOTSEL reset. Connect the Pico with a data cable while holding BOOTSEL, or pass --volume /Volumes/RPI-RP2 to use an already-mounted BOOTSEL volume."
    )
  }

  // MARK: - debug

  static func debug(_ arguments: [String]) throws {
    let project = try context(arguments)
    let config = project.config
    let openOCD = option("--openocd", in: arguments) ?? config.openOCD
    let files = config.openOCDConfig
    guard !files.isEmpty else {
      throw CLIError.message(
        "set 'openOCDConfig' in swiftpico.json (for example interface/cmsis-dap.cfg,target/rp2040.cfg)"
      )
    }
    var command = [openOCD] + files.flatMap { ["-f", $0] }
    if let target = option("--target", in: arguments) {
      command += ["-c", "target remote \(target)"]
    }
    print("Starting OpenOCD: \(command.joined(separator: " "))")
    try runProcess(command, currentDirectory: project.root)
  }

}
