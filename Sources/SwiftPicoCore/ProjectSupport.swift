import Foundation
import Dispatch
#if os(macOS)
import Darwin
#else
import Glibc
#endif

extension SwiftPicoCommand {
    static func showInfo(_ arguments: [String]) throws {
        let project = try context(arguments)
        let config = project.config
        print("=== PicoKit Project Info ===")
        print("  Root:        \(project.root.path)")
        print("  Board:       \(config.board)")
        print("  Product:     \(config.product ?? "default")")
        print("  Config:      \(config.configuration)")
        print("  Firmware:    \(config.firmwareDirectory ?? "SwiftPM")")
        print("  Swift SDK:   \(config.swiftSDK ?? "not set")")
        print("  UF2 path:    \(config.uf2 ?? "not set")")
        print("  OpenOCD:     \(config.openOCD)")
        print("  OpenOCD cfg: \(config.openOCDConfig.joined(separator: ", "))")

        if let uf2 = config.uf2, FileManager.default.fileExists(atPath: project.url(for: uf2).path) {
            let attrs = try FileManager.default.attributesOfItem(atPath: project.url(for: uf2).path)
            if let size = attrs[.size] as? Int {
                print("  UF2 size:    \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
            }
        }
    }

    static let usage = """
    SwiftPico — project tooling for PicoKit and Raspberry Pi Pico/Pico 2

    Commands:
      init    [--board BOARD] [--name NAME] [--template TPL] [--force]
              [--path PATH] [--pico-kit-url URL] [--pico-kit-version VERSION]
              [--pico-kit-path PATH]
              [--skip-resolve]
          Create a standalone PicoKit project with a SwiftPM dependency
      new     Alias for init
      add swift --url URL --from VERSION --package PACKAGE --product PRODUCT
                [--target TARGET] [--skip-resolve]
          Add an Embedded Swift package target to Package.swift and firmware
      add c|cpp --url URL --tag TAG --target CMAKE_TARGET [--name NAME]
          Add and lock a C/C++ CMake target into firmware
      dependencies resolve|generate|remove NAME|update NAME --revision REV|migrate|show
          Manage dependencies.json, dependencies.lock, and generated CMake
      build, b [--configuration debug|release] [--swift-sdk SDK] [--product P]
              Build the firmware
      clean, c Remove build artifacts
      flash, f [--uf2 PATH] [--volume PATH]
              Flash over USB with picotool or USB CDC reset; --volume uses
              mounted BOOTSEL storage explicitly
      upload  Alias for flash
      make, m Build then flash
      debug   [--openocd PATH] [--target TARGET]
              Start OpenOCD debug session
      monitor, serial, mon [--device /dev/cu.usbmodem…] [--baud 115200]
          [--reconnect] Interactive serial terminal; optionally reconnect after reset
      list, devices
              Show Pico boot volumes and serial devices
      info    Show current project configuration
      template List available project templates
      doctor   Check the host toolchain, SDK bridge, boot volume, and serial devices

    Boards: pico, pico_w, pico2, pico2_w (pico-w and pico2-w accepted as input)

    Commands locate swiftpico.json (or legacy picokit.json) in the current directory or a parent directory.
    Generated projects include ./swiftpico, so use swiftpico build, flash, or monitor.
    """
}
