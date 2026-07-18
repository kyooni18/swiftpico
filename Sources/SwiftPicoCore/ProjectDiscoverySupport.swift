import Foundation

extension SwiftPicoCommand {
  static func validateArguments(command: String, arguments: [String]) throws {
    if command == "dependencies" || command == "deps" {
      guard let action = arguments.first,
        ["resolve", "generate", "remove", "update", "migrate", "show"].contains(action)
      else {
        throw CLIError.message(
          "usage: swiftpico dependencies resolve|generate|remove|update|migrate|show")
      }
      let consumesName = action == "remove" || action == "update"
      if consumesName {
        guard arguments.count >= 2, !arguments[1].hasPrefix("--") else {
          throw CLIError.message("usage: swiftpico dependencies \(action) NAME")
        }
      }
      let remainder = Array(arguments.dropFirst(consumesName ? 2 : 1))
      try validateLibraryArguments(remainder)
      return
    }
    if command == "add" {
      guard let kind = arguments.first, ["swift", "c", "cpp", "cxx"].contains(kind) else {
        throw CLIError.message("usage: swiftpico add swift|c [options]")
      }
      try validateLibraryArguments(Array(arguments.dropFirst()))
      return
    }
    let canonicalCommand: [String: String] = [
      "new": "init", "b": "build", "f": "flash", "m": "make", "c": "clean",
      "mon": "monitor", "diagnose": "doctor", "help": "help", "--help": "help", "-h": "help",
    ]
    let schemas: [String: (valued: Set<String>, flags: Set<String>)] = [
      "init": (["--board", "--name", "--template", "--path", "--pico-kit-url", "--pico-kit-version", "--pico-kit-path"], ["--force", "--skip-resolve"]),
      "build": (["--configuration", "--swift-sdk", "--product", "--context"], ["--verbose"]),
      "clean": (["--context"], []),
      "flash": (["--uf2", "--volume", "--picotool", "--context"], ["--force-unknown-volume"]),
      "upload": (["--uf2", "--volume", "--picotool", "--context"], ["--force-unknown-volume"]),
      "debug": (["--openocd", "--target", "--context"], []),
      "monitor": (["--device", "--baud", "--context"], ["--reconnect"]),
      "serial": (["--device", "--baud", "--context"], ["--reconnect"]),
      "info": (["--context"], []),
      "doctor": ([], []), "devices": ([], []), "list": ([], []), "template": ([], []), "help": ([], []),
      "make": (["--configuration", "--swift-sdk", "--product", "--context", "--uf2", "--volume", "--picotool"], ["--verbose", "--force-unknown-volume"]),
    ]
    guard let schema = schemas[canonicalCommand[command] ?? command] else {
      throw CLIError.message("unsupported command '\(command)'")
    }
    let valued = schema.valued
    let flags = schema.flags
    var seen = Set<String>()
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      guard argument.hasPrefix("--") else {
        throw CLIError.message("unexpected argument '\(argument)' for \(command)")
      }
      guard seen.insert(argument).inserted else {
        throw CLIError.message("duplicate option '\(argument)' for \(command)")
      }
      if valued.contains(argument) {
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
          throw CLIError.message("\(argument) requires a value")
        }
        index += 2
      } else if flags.contains(argument) {
        index += 1
      } else {
        throw CLIError.message("unknown option '\(argument)' for \(command)")
      }
    }
  }

  static func validateLibraryArguments(_ arguments: [String]) throws {
    let valued: Set<String> = [
      "--url", "--from", "--package", "--product", "--target", "--tag", "--name", "--context",
      "--revision",
    ]
    let flags: Set<String> = ["--skip-resolve"]
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      if valued.contains(argument) {
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
          throw CLIError.message("\(argument) requires a value")
        }
        index += 2
      } else if flags.contains(argument) {
        index += 1
      } else {
        throw CLIError.message("unknown option '\(argument)' for add")
      }
    }
  }

  static func context(_ arguments: [String]) throws -> ProjectContext {
    let currentDirectory = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let configURL: URL
    if let path = option("--context", in: arguments) {
      configURL = URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
    } else if let discovered = findContext(from: currentDirectory) {
      configURL = discovered
    } else {
      throw CLIError.message(
        "no swiftpico.json or picokit.json found in this directory or its parents. Run 'swiftpico init --board pico' first, or pass --context /path/to/project.json."
      )
    }
    guard FileManager.default.fileExists(atPath: configURL.path) else {
      throw CLIError.message("project context not found: \(configURL.path)")
    }
    let config = try JSONDecoder().decode(PicoKitConfig.self, from: Data(contentsOf: configURL))
    _ = try ProjectSchemaMigration.required(for: config.schemaVersion)
    _ = try canonicalBoard(config.board)
    return ProjectContext(root: configURL.deletingLastPathComponent(), config: config)
  }

  static func findContext(from directory: URL) -> URL? {
    var candidate = directory.standardizedFileURL
    while true {
      for name in ["swiftpico.json", "picokit.json"] {
        let context = candidate.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: context.path) { return context }
      }
      let parent = candidate.deletingLastPathComponent()
      guard parent.path != candidate.path else { return nil }
      candidate = parent
    }
  }

  static func findPicoKitRoot(from directory: URL) -> URL? {
    var candidate = directory
    while candidate.path != "/" {
      let package = candidate.appendingPathComponent("Package.swift").path
      let library = candidate.appendingPathComponent("Sources/PicoKitFacade").path
      if FileManager.default.fileExists(atPath: package),
        FileManager.default.fileExists(atPath: library)
      {
        return candidate
      }
      candidate.deleteLastPathComponent()
    }
    return nil
  }

  static func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  static func cmakeExecutable() -> String {
    #if os(macOS)
      // Codex and remote-development environments can prepend an x86-only
      // CMake to PATH on Apple Silicon. Pico SDK builds pioasm as a native
      // host tool, so use the native Homebrew CMake when it is installed.
      let homebrewCMake = "/opt/homebrew/bin/cmake"
      if FileManager.default.isExecutableFile(atPath: homebrewCMake) {
        return homebrewCMake
      }
    #endif
    return "cmake"
  }

  static func ninjaExecutable() -> String {
    #if os(macOS)
      let homebrewNinja = "/opt/homebrew/bin/ninja"
      if FileManager.default.isExecutableFile(atPath: homebrewNinja) {
        return homebrewNinja
      }
    #endif
    return "ninja"
  }

  static func swiftCompilerPath() -> String? {
    let fileManager = FileManager.default
    var candidates: [String] = []
    if let explicit = ProcessInfo.processInfo.environment["PICO_SWIFTC"], !explicit.isEmpty {
      candidates.append(explicit)
    }
    if let toolchains = ProcessInfo.processInfo.environment["SWIFTLY_TOOLCHAINS_DIR"],
      let installed = try? fileManager.contentsOfDirectory(atPath: toolchains)
    {
      candidates.append(
        contentsOf:
          installed
          .filter { $0.hasPrefix("swift-DEVELOPMENT-SNAPSHOT-") && $0.hasSuffix(".xctoolchain") }
          .sorted(by: >)
          .map {
            URL(fileURLWithPath: toolchains)
              .appendingPathComponent($0)
              .appendingPathComponent("usr/bin/swiftc").path
          })
    }
    if let path = ProcessInfo.processInfo.environment["PATH"] {
      candidates.append(
        contentsOf: path.split(separator: ":").map {
          URL(fileURLWithPath: String($0)).appendingPathComponent("swiftc").path
        })
    }
    if let toolchains = ProcessInfo.processInfo.environment["SWIFTLY_TOOLCHAINS_DIR"] {
      candidates.append(
        URL(fileURLWithPath: toolchains)
          .appendingPathComponent("swift-latest.xctoolchain/usr/bin/swiftc").path)
    }
    candidates.append(contentsOf: [
      "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
      "/usr/bin/swiftc",
    ])
    return candidates.first {
      fileManager.isExecutableFile(atPath: $0) && !$0.hasSuffix("/.swiftly/bin/swiftc")
    }
  }
}
