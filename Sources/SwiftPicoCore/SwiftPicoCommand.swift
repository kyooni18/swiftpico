import Dispatch
import Foundation

#if os(macOS)
  import Darwin
#else
  import Glibc
#endif

public enum SwiftPicoCommand {
  static let defaultPicoKitURL = "https://github.com/kyooni18/PicoKit.git"
  static let offlinePicoKitVersion = "0.2.11"
  static let releaseVersion = SwiftPicoVersion.current

  static let firmwareProjectManifest = """
    cmake_minimum_required(VERSION 3.29)

    if(NOT DEFINED PICOKIT_ROOT)
        message(FATAL_ERROR "PICOKIT_ROOT must point to the resolved PicoKit package checkout")
    endif()

    if(NOT DEFINED PICO_SDK_PATH)
        message(FATAL_ERROR "PICO_SDK_PATH must point to the shared Pico SDK. Run 'swiftpico build' or pass -DPICO_SDK_PATH=/path/to/pico-sdk.")
    endif()
    include("${PICO_SDK_PATH}/external/pico_sdk_import.cmake")
    project(PicoKitFirmware LANGUAGES C CXX ASM)
    set(PICOKIT_PROJECT_INITIALIZED YES)
    include("${PICOKIT_ROOT}/Firmware/CMakeLists.txt")

    # USB configuration is supplied by `swiftpico build` from
    # initialize_usb_interface_at_start in swiftpico.json.
    """

  static let projectRunner = """
    #!/bin/sh
    exec "${SWIFTPICO:-swiftpico}" "$@"
    """

  public static func main() {
    do {
      try run(Array(CommandLine.arguments.dropFirst()))
    } catch {
      FileHandle.standardError.write(Data("swiftpico: \(error.localizedDescription)\n".utf8))
      Foundation.exit(1)
    }
  }

  static func run(_ arguments: [String]) throws {
    guard let command = arguments.first else { throw CLIError.usage }
    let args = Array(arguments.dropFirst())
    try validateArguments(command: command, arguments: args)
    switch command {
    case "help", "--help", "-h": print(usage)
    case "init", "new": try initialise(args)
    case "add":
      try runStage(
        "dependency update",
        recovery: "check the dependency arguments and run 'swiftpico dependencies resolve'"
      ) { try addLibrary(args) }
    case "dependencies", "deps":
      try runStage(
        "dependency management",
        recovery: "inspect Firmware/dependencies.json, then run 'swiftpico dependencies resolve'"
      ) { try dependencies(args) }
    case "build", "b": try build(args)
    case "flash", "upload", "f":
      try runStage(
        "flash",
        recovery: "run 'swiftpico devices', reconnect the board with a data cable, and retry"
      ) { try flash(args) }
    case "make", "m":
      try build(args)
      try runStage(
        "flash",
        recovery: "run 'swiftpico devices', reconnect the board with a data cable, and retry"
      ) { try flash(args) }
    case "clean", "c": try clean(args)
    case "debug": try debug(args)
    case "monitor", "serial", "mon": try monitor(args)
    case "list", "devices": list()
    case "info": try showInfo(args)
    case "template": showTemplates(args)
    case "doctor", "diagnose": try doctor(args)
    default: throw CLIError.message("unknown command '\(command)'\n\n\(usage)")
    }
  }

  static func runStage(_ stage: String, recovery: String, operation: () throws -> Void) throws {
    do {
      try operation()
    } catch let failure as StageFailure {
      throw failure
    } catch {
      throw StageFailure(
        stage: stage,
        subject: FileManager.default.currentDirectoryPath,
        recovery: recovery,
        underlying: error
      )
    }
  }

}
