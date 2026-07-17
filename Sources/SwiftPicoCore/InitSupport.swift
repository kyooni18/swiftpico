import Dispatch
import Foundation

#if os(macOS)
  import Darwin
#else
  import Glibc
#endif

extension SwiftPicoCommand {
  static func initialise(_ arguments: [String]) throws {
    let requestedBoard = option("--board", in: arguments) ?? "pico"
    guard let picoBoard = PicoBoard(configurationName: requestedBoard) else {
      throw CLIError.message(
        "unsupported board '\(requestedBoard)'. Choose: pico, pico_w, pico2, pico2_w")
    }
    let board = picoBoard.rawValue
    let name = option("--name", in: arguments) ?? "PicoApp"
    let template = option("--template", in: arguments) ?? "blink"
    guard availableTemplates.contains(template) else {
      throw CLIError.message(
        "unknown template '\(template)'. Run 'swiftpico template' to list supported templates.")
    }
    let force = arguments.contains("--force")
    let currentDirectory = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let picoKitURL = option("--pico-kit-url", in: arguments) ?? Self.defaultPicoKitURL
    let picoKitPath = option("--pico-kit-path", in: arguments).map {
      URL(fileURLWithPath: $0, relativeTo: currentDirectory).standardizedFileURL
    }
    let skipResolve = arguments.contains("--skip-resolve")
    print("Starting SwiftPico project initialization…")
    print("  Board: \(board)")
    print("  Name: \(name)")
    print("  Template: \(template)")
    print("  Destination: \(currentDirectory.appendingPathComponent(name).path)")
    // Project creation is deterministic: it never asks the network for a
    // newer tag. Version changes are an explicit dependency operation.
    let picoKitVersion = option("--pico-kit-version", in: arguments) ?? Self.offlinePicoKitVersion
    let projectRoot: URL
    if let path = option("--path", in: arguments) {
      projectRoot = URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
    } else {
      projectRoot = currentDirectory.appendingPathComponent(name, isDirectory: true)
    }
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

    let configURL = projectRoot.appendingPathComponent("swiftpico.json")
    guard force || !FileManager.default.fileExists(atPath: configURL.path) else {
      throw CLIError.message("swiftpico.json already exists. Use --force to overwrite.")
    }

    let target = firmwareTargetName(name)
    let config = PicoKitConfig(
      board: board,
      firmwareDirectory: "Firmware",
      picoSDKPath: nil,
      picoKitPath: picoKitPath?.path,
      picoKitURL: picoKitURL,
      picoKitVersion: picoKitVersion,
      picotool: nil,
      swiftSDK: nil,
      initializeUSBInterfaceAtStart: true,
      product: name,
      configuration: "release",
      uf2: "Firmware/build/\(target).uf2",
      openOCD: "openocd",
      openOCDConfig: picoBoard.chip == .rp2350
        ? ["interface/cmsis-dap.cfg", "target/rp2350.cfg"]
        : ["interface/cmsis-dap.cfg", "target/rp2040.cfg"]
    )
    print("Creating project configuration and source files…")
    try JSONEncoder.pretty.encode(config).write(to: configURL)

    let manifest = projectManifest(
      name: name,
      target: target,
      picoKitURL: picoKitURL,
      picoKitVersion: picoKitVersion,
      picoKitPath: picoKitPath?.path
    )
    try manifest.write(
      to: projectRoot.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

    let sourceDir = projectRoot.appendingPathComponent("Sources").appendingPathComponent(name)
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    let sourceFile = sourceDir.appendingPathComponent("main.swift")

    guard !FileManager.default.fileExists(atPath: sourceFile.path) || force else {
      print("Source file already exists at \(sourceFile.path)")
      return
    }

    let sourceCode = templateSource(template: template, board: board, name: name)
    try sourceCode.write(to: sourceFile, atomically: true, encoding: .utf8)

    let firmwareDir = projectRoot.appendingPathComponent("Firmware", isDirectory: true)
    try FileManager.default.createDirectory(at: firmwareDir, withIntermediateDirectories: true)
    try firmwareProjectManifest.write(
      to: firmwareDir.appendingPathComponent("CMakeLists.txt"),
      atomically: true,
      encoding: .utf8
    )
    print("Preparing firmware dependency metadata…")
    try DependencySupport.initializeProject(at: projectRoot)

    let runner = projectRoot.appendingPathComponent("swiftpico")
    try projectRunner.write(to: runner, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runner.path)

    try """
    .build/
    Firmware/build/
    Firmware/Dependencies.local.cmake
    *.uf2
    """.write(
      to: projectRoot.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

    if !skipResolve {
      print("Resolving PicoKit and Swift package dependencies…")
      if picoKitPath == nil {
        _ = try installPicoKitDependency(projectRoot: projectRoot, config: config)
      } else {
        print("  Resolving local PicoKit checkout at \(picoKitPath!.path)…")
        try runProcess(["swift", "package", "resolve"], currentDirectory: projectRoot)
      }
      print("  Locking PicoKit and firmware dependencies…")
      _ = try DependencySupport.resolve(
        root: projectRoot,
        picoKitURL: picoKitURL,
        picoKitVersion: picoKitVersion,
        picoKitPath: picoKitPath?.path
      )
      print("  Dependency lock and generated CMake are ready.")
    } else if picoKitPath != nil {
      print("Skipping Swift package resolution; recording the local PicoKit checkout…")
      _ = try DependencySupport.resolve(
        root: projectRoot,
        picoKitURL: picoKitURL,
        picoKitVersion: picoKitVersion,
        picoKitPath: picoKitPath?.path
      )
    } else {
      print("Skipping dependency resolution (--skip-resolve).")
    }

    print(
      """
      Project '\(name)' created for board '\(board)'.
      Project directory: \(projectRoot.path)

      Files created:
        - swiftpico.json
        - Package.swift (PicoKit dependency: \(picoKitPath?.path ?? picoKitURL), version \(picoKitVersion))
        - \(sourceFile.path)
        - Firmware/CMakeLists.txt
        - Firmware/dependencies.json
        - Firmware/Interop/AppInterop.h
        - swiftpico

      Next steps:
        1. cd \(projectRoot.path)
        2. Run: swiftpico build
        3. Run: swiftpico flash
      """)
  }

}
