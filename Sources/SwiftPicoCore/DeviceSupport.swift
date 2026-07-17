import Dispatch
import Foundation

#if os(macOS)
  import Darwin
#else
  import Glibc
#endif

extension SwiftPicoCommand {
  static func serialDevices() -> [String] {
    let devices =
      (try? FileManager.default.contentsOfDirectory(atPath: "/dev"))?.filter {
        $0.hasPrefix("cu.usb") || $0.hasPrefix("ttyACM") || $0.hasPrefix("ttyUSB")
      } ?? []
    return devices.sorted().map { "/dev/\($0)" }
  }

  static func resetToBootloaderOverUSB() throws {
    let devices = serialDevices()
    guard devices.count == 1, let device = devices.first else {
      let hint =
        devices.isEmpty
        ? "no USB serial device found"
        : "multiple USB serial devices found (passive reset needs exactly one)"
      throw CLIError.message("cannot request BOOTSEL reset: \(hint)")
    }

    // The Pico SDK treats 1200 baud as a USB CDC request to reboot into
    // BOOTSEL. macOS may block inside termios for an unresponsive CDC
    // endpoint, so keep the compatibility command in a short-lived child
    // that is forcibly terminated instead of allowing flash to wedge.
    #if os(macOS)
      try runProcess(["stty", "-f", device, "1200", "raw", "-echo"], quiet: true, timeout: 2)
    #else
      try runProcess(["stty", "-F", device, "1200", "raw", "-echo"], quiet: true, timeout: 2)
    #endif
  }

  static func waitForBootVolume(timeout: TimeInterval = 8) -> URL? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let volume = findBootVolume() { return volume }
      Thread.sleep(forTimeInterval: 0.25)
    } while Date() < deadline
    return nil
  }

  static func flashBootloader(_ source: URL, volume: URL, picotool: String?) throws {
    if let picotool {
      print("Flashing \(source.lastPathComponent) over USB with picotool…")
      try runProcess([picotool, "load", "-v", source.path])
      try runProcess([picotool, "reboot", "--application"])
      print("Flashed and verified \(source.lastPathComponent) over USB.")
    } else {
      try copyUF2ToVolume(source, volume: volume)
      print("Flashed \(source.lastPathComponent) to \(volume.path); Pico is restarting.")
    }
  }

  static func waitForApplication(
    _ config: PicoKitConfig,
    bootVolume: URL? = nil,
    timeout: TimeInterval = 12
  ) throws {
    func bootVolumeIsPresent() -> Bool {
      if let bootVolume {
        return FileManager.default.fileExists(atPath: bootVolume.path)
      }
      return findBootVolume() != nil
    }

    let deadline = Date().addingTimeInterval(timeout)
    var bootVolumeHasGone = !bootVolumeIsPresent()
    repeat {
      if !bootVolumeHasGone {
        bootVolumeHasGone = !bootVolumeIsPresent()
      }
      if bootVolumeHasGone,
        !config.initializesUSBInterfaceAtStart || !serialDevices().isEmpty
      {
        print(
          config.initializesUSBInterfaceAtStart
            ? "Pico restarted and USB serial is ready."
            : "Pico restarted in application mode.")
        return
      }
      Thread.sleep(forTimeInterval: 0.25)
    } while Date() < deadline

    if !bootVolumeHasGone {
      throw CLIError.message("UF2 transfer completed, but the Pico remained in BOOTSEL mode")
    }
    throw CLIError.message(
      "UF2 transfer completed, but the Pico USB serial interface did not return within \(Int(timeout)) seconds"
    )
  }

  static func isToolAvailable(_ executable: String) -> Bool {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    return path.split(separator: ":").contains { directory in
      FileManager.default.isExecutableFile(atPath: "\(directory)/\(executable)")
    }
  }

  static func findBootVolume() -> URL? {
    // Finder and Disk Arbitration can expose a newly mounted FAT volume
    // before `mountedVolumeURLs` refreshes its metadata. Check the normal
    // macOS mount paths directly first.
    for path in ["/Volumes/RP2350", "/Volumes/RPI-RP2350", "/Volumes/RPI-RP2"] {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        return URL(fileURLWithPath: path, isDirectory: true)
      }
    }
    let volumes =
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: [.volumeNameKey], options: []) ?? []
    return volumes.first(where: isPicoBootVolume)
  }

  static func findPicotool(_ config: PicoKitConfig, projectRoot: URL) -> String? {
    var candidates = [
      projectRoot.appendingPathComponent("Tools/picotool-build/picotool").path,
      "/opt/homebrew/bin/picotool",
      "/usr/local/bin/picotool",
    ]
    if let path = ProcessInfo.processInfo.environment["PATH"] {
      candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/picotool" })
    }
    if let configured = config.picotool {
      candidates.insert(
        configured.hasPrefix("/")
          ? configured : projectRoot.appendingPathComponent(configured).standardizedFileURL.path,
        at: 0
      )
    }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  static func copyUF2ToVolume(_ source: URL, volume: URL) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: volume.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw CLIError.message("Pico boot volume is not mounted at \(volume.path)")
    }
    let destination = volume.appendingPathComponent(source.lastPathComponent)
    let deadline = Date().addingTimeInterval(5)
    var lastError: Error?

    repeat {
      do {
        // The freshly mounted FAT volume can briefly reject writes.
        #if os(macOS)
          try runProcess(
            ["env", "COPYFILE_DISABLE=1", "cp", "-X", source.path, destination.path], quiet: true)
        #else
          if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
          }
          try FileManager.default.copyItem(at: source, to: destination)
        #endif
        return
      } catch {
        lastError = error
        Thread.sleep(forTimeInterval: 0.25)
      }
    } while Date() < deadline

    throw lastError ?? CLIError.message("could not copy UF2 to \(destination.path)")
  }

  static func isPicoBootVolume(_ volume: URL) -> Bool {
    let name = (try? volume.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? ""
    return ["RPI-RP2", "RPI-RP2350", "RP2350"].contains(name)
  }

}
