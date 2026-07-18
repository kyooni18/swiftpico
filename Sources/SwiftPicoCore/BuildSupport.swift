import Dispatch
import Foundation

#if os(macOS)
  import Darwin
#else
  import Glibc
#endif

extension SwiftPicoCommand {
  static func build(_ arguments: [String]) throws {
    let project = try context(arguments)
    if FileManager.default.fileExists(
      atPath: project.root.appendingPathComponent(DependencySupport.manifestPath).path)
    {
      try DependencySupport.generateFromLock(root: project.root)
    }
    let config = project.config
    if let firmwareDirectory = config.firmwareDirectory {
      let configuration = option("--configuration", in: arguments) ?? config.configuration
      guard ["debug", "release"].contains(configuration.lowercased()) else {
        throw CLIError.message("configuration must be 'debug' or 'release', not '\(configuration)'")
      }
      let toolchainPath = ProcessInfo.processInfo.environment["PICO_TOOLCHAIN_PATH"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if ProcessInfo.processInfo.environment["PICO_TOOLCHAIN_PATH"] != nil,
        toolchainPath?.isEmpty != false
      {
        throw CLIError.message(
          "PICO_TOOLCHAIN_PATH is empty. Unset it or set it to a directory containing arm-none-eabi-gcc.")
      }
      let configuredCompiler = toolchainPath.map {
        URL(fileURLWithPath: $0).appendingPathComponent("bin/arm-none-eabi-gcc").path
      }
      let configuredFlatCompiler = toolchainPath.map {
        URL(fileURLWithPath: $0).appendingPathComponent("arm-none-eabi-gcc").path
      }
      if let toolchainPath, !toolchainPath.isEmpty,
        !FileManager.default.fileExists(atPath: toolchainPath)
          || (!(configuredCompiler.map(FileManager.default.isExecutableFile(atPath:)) ?? false)
            && !(configuredFlatCompiler.map(FileManager.default.isExecutableFile(atPath:)) ?? false))
      {
        throw CLIError.message(
          "PICO_TOOLCHAIN_PATH is invalid: \(toolchainPath). Expected a directory containing bin/arm-none-eabi-gcc.")
      }
      guard isToolAvailable("arm-none-eabi-gcc") || configuredCompiler.map(FileManager.default.isExecutableFile(atPath:)) == true || configuredFlatCompiler.map(FileManager.default.isExecutableFile(atPath:)) == true else {
        throw CLIError.message(
          "arm-none-eabi-gcc was not found. Install the Pico SDK ARM toolchain or set PICO_TOOLCHAIN_PATH, then run 'swiftpico doctor'."
        )
      }
      let firmwareURL = try project.projectBoundURL(
        for: firmwareDirectory, label: "firmwareDirectory")
      let buildDirectory = firmwareURL.appendingPathComponent("build", isDirectory: true)
      let cmake = cmakeExecutable()
      let ninja = ninjaExecutable()
      var configure = [
        cmake, "-S", firmwareURL.path, "-B", buildDirectory.path,
        "-G", "Ninja", "-DCMAKE_MAKE_PROGRAM=\(ninja)",
        "-DCMAKE_BUILD_TYPE=\(configuration.capitalized)",
        "-DPICO_BOARD=\(try canonicalBoard(config.board).cmakeName)",
      ]
      let sourceName = option("--product", in: arguments) ?? config.product ?? "PicoKitFirmware"
      guard sourceName.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
        throw CLIError.message(
          "invalid firmware product \(String(reflecting: sourceName)). Use letters, digits, '_' or '-' only.")
      }
      guard sourceName != ".", sourceName != ".." else {
        throw CLIError.message("invalid firmware product \(String(reflecting: sourceName))")
      }
      let product = firmwareTargetName(sourceName)
      let sourcesRoot = project.root.appendingPathComponent("Sources", isDirectory: true).standardizedFileURL
      let sourceURL = sourcesRoot.appendingPathComponent(sourceName, isDirectory: true)
        .appendingPathComponent("main.swift").standardizedFileURL
      guard sourceURL.path.hasPrefix(sourcesRoot.path + "/") else {
        throw CLIError.message("firmware product source must remain within Sources/")
      }
      configure += [
        "-DPICOKIT_PRODUCT=\(product)",
        "-DPICOKIT_SOURCE=\(sourceURL.path)",
      ]
      configure.append(
        "-DPICOKIT_ENABLE_USB=\(config.initializesUSBInterfaceAtStart ? "ON" : "OFF")")
      let picoKitRoot = try resolvePicoKitRoot(project: project, config: config)
      let picoKitVersion = persistedPicoKitVersion(
        project: project, fallback: config.picoKitVersion)
      let buildState = FirmwareBuildState(
        swiftPicoVersion: Self.releaseVersion,
        picoKitVersion: picoKitVersion
      )
      try invalidateFirmwareBuildIfNeeded(
        buildDirectory: buildDirectory,
        stateURL: project.root.appendingPathComponent(".swiftpico/firmware-build.json"),
        expected: buildState
      )
      configure.append("-DPICOKIT_ROOT=\(picoKitRoot.path)")
      if let picoSDKPath = config.picoSDKPath {
        let sdkURL = project.url(for: picoSDKPath)
        configure.append("-DPICO_SDK_PATH=\(sdkURL.path)")
      } else {
        let sdkURL = try sharedPicoSDK(for: picoKitRoot)
        configure.append("-DPICO_SDK_PATH=\(sdkURL.path)")
      }
      if try canonicalBoard(config.board).chip == .rp2350 {
        configure.append("-DPICO_PLATFORM=rp2350-arm-s")
      }
      if let swiftCompiler = swiftCompilerPath() {
        // Swiftly's ~/.swiftly/bin/swiftc is a dispatch proxy. CMake
        // invokes the compiler directly, so use the real toolchain
        // binary to avoid Swiftly recursively dispatching itself.
        configure.append("-DCMAKE_Swift_COMPILER=\(swiftCompiler)")
      }
      if arguments.contains("--verbose") {
        configure.append("-DCMAKE_VERBOSE_MAKEFILE=ON")
      }
      print("Configuring firmware: \(configure.joined(separator: " "))")
      do {
        try runProcess(configure)
      } catch {
        throw StageFailure(
          stage: "configure", subject: buildDirectory.path,
          recovery: "run 'swiftpico doctor', then 'swiftpico clean' and retry the build",
          underlying: error)
      }
      let build = [cmake, "--build", buildDirectory.path]
      print("Building firmware: \(build.joined(separator: " "))")
      do {
        try runProcess(build)
      } catch {
        throw StageFailure(
          stage: "compile", subject: buildDirectory.path,
          recovery: "inspect the first compiler error; use --verbose for the complete command",
          underlying: error)
      }
      try writeFirmwareBuildState(
        buildState, to: project.root.appendingPathComponent(".swiftpico/firmware-build.json"))
      print("Firmware build succeeded.")
      return
    }
    guard let sdk = option("--swift-sdk", in: arguments) ?? config.swiftSDK else {
      throw CLIError.message(
        "no Swift Embedded SDK is configured. Install one, then set 'swiftSDK' in swiftpico.json or pass --swift-sdk <id>. Refusing to build a host executable that cannot be flashed to \(config.board)."
      )
    }
    var command = [
      "swift", "build", "-c", option("--configuration", in: arguments) ?? config.configuration,
    ]
    command += ["--swift-sdk", sdk]
    if let product = option("--product", in: arguments) ?? config.product {
      command += ["--product", product]
    }
    if arguments.contains("--verbose") { command += ["--verbose"] }
    print("Building: \(command.joined(separator: " "))")
    try runProcess(command, currentDirectory: project.root)
    print("Build succeeded.")
  }

  // MARK: - clean

  static func clean(_ arguments: [String]) throws {
    let project = try context(arguments)
    let config = project.config
    print("Cleaning build artifacts...")
    if let firmwareDirectory = config.firmwareDirectory {
      let firmwareURL = try project.projectBoundURL(
        for: firmwareDirectory, label: "firmwareDirectory")
      let buildDirectory = firmwareURL
        .appendingPathComponent("build", isDirectory: true)
      if FileManager.default.fileExists(atPath: buildDirectory.path) {
        try FileManager.default.removeItem(at: buildDirectory)
      }
    } else {
      try runProcess(["swift", "package", "clean"], currentDirectory: project.root)
    }
    print("Clean complete.")
  }

}
