import Foundation

extension SwiftPicoCommand {
  static func resolvePicoKitRoot(project: ProjectContext, config: PicoKitConfig) throws -> URL {
    if let configuredPath = config.picoKitPath {
      let root = project.url(for: configuredPath)
      guard
        FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path)
      else {
        throw CLIError.message("PicoKit checkout not found at \(root.path)")
      }
      return root
    }

    let checkout = project.root.appendingPathComponent(
      ".build/checkouts/PicoKit", isDirectory: true)
    if FileManager.default.fileExists(
      atPath: project.root.appendingPathComponent(DependencySupport.manifestPath).path),
      !FileManager.default.fileExists(atPath: checkout.appendingPathComponent("Package.swift").path)
    {
      throw CLIError.message(
        "locked PicoKit checkout is missing; run 'swiftpico dependencies resolve' before building")
    }
    return try installPicoKitDependency(projectRoot: project.root, config: config)
  }

  static func clearPicoKitRepoCache(projectRoot: URL) throws {
    let reposDir = projectRoot.appendingPathComponent(".build/repositories", isDirectory: true)
    guard FileManager.default.fileExists(atPath: reposDir.path) else { return }
    let entries = try FileManager.default.contentsOfDirectory(atPath: reposDir.path)
    for entry in entries where entry.hasPrefix("PicoKit-") {
      try FileManager.default.removeItem(at: reposDir.appendingPathComponent(entry))
    }
  }

  static func persistedPicoKitVersion(project: ProjectContext, fallback: String?) -> String {
    let configURL = project.root.appendingPathComponent("swiftpico.json")
    let persisted = try? JSONDecoder().decode(PicoKitConfig.self, from: Data(contentsOf: configURL))
    return persisted?.picoKitVersion ?? fallback ?? "local"
  }

  static func invalidateFirmwareBuildIfNeeded(
    buildDirectory: URL,
    stateURL: URL,
    expected: FirmwareBuildState
  ) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: buildDirectory.path) else { return }

    let existing = try? JSONDecoder().decode(
      FirmwareBuildState.self, from: Data(contentsOf: stateURL))
    guard existing != expected else { return }

    let previous =
      existing.map {
        "SwiftPico \($0.swiftPicoVersion), PicoKit \($0.picoKitVersion)"
      } ?? "an unknown earlier build"
    print(
      "Build versions changed (\(previous) → SwiftPico \(expected.swiftPicoVersion), PicoKit \(expected.picoKitVersion)); rebuilding firmware from scratch."
    )
    try fileManager.removeItem(at: buildDirectory)
  }

  static func writeFirmwareBuildState(_ state: FirmwareBuildState, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.pretty.encode(state).write(to: url, options: .atomic)
  }

  static func installPicoKitDependency(projectRoot: URL, config: PicoKitConfig) throws -> URL {
    let checkout = projectRoot.appendingPathComponent(".build/checkouts/PicoKit", isDirectory: true)

    if !FileManager.default.fileExists(
      atPath: checkout.appendingPathComponent("Package.swift").path)
    {
      try clearPicoKitRepoCache(projectRoot: projectRoot)
      print("  PicoKit checkout missing; resolving the requested package revision…")
    } else {
      print("  PicoKit checkout already present; refreshing Swift package resolution…")
    }

    do {
      try runProcess(["swift", "package", "resolve"], currentDirectory: projectRoot)
    } catch {
      try clearPicoKitRepoCache(projectRoot: projectRoot)
      try runProcess(["swift", "package", "resolve"], currentDirectory: projectRoot)
    }

    guard
      FileManager.default.fileExists(atPath: checkout.appendingPathComponent("Package.swift").path)
    else {
      throw CLIError.message("PicoKit dependency was not resolved at \(checkout.path)")
    }

    // Published PicoKit versions before the shared-cache transition still
    // contain the SDK submodule. Preserve their install path so updating
    // SwiftPico does not break existing pinned projects.
    let revision = checkout.appendingPathComponent("Vendor/pico-sdk.revision")
    let legacySDK = checkout.appendingPathComponent("Vendor/pico-sdk", isDirectory: true)
    if !FileManager.default.fileExists(atPath: revision.path),
      !FileManager.default.fileExists(
        atPath: legacySDK.appendingPathComponent("CMakeLists.txt").path)
    {
      print("  PicoKit release uses the legacy Pico SDK submodule; initializing it…")
      try runProcess(
        ["git", "-C", checkout.path, "submodule", "update", "--init", "--recursive"],
        currentDirectory: projectRoot)
    }
    _ = try sharedPicoSDK(for: checkout)
    return checkout
  }

  /// PicoKit pins the SDK revision in a tiny tracked file. The full SDK is
  /// materialized once in a user cache, rather than once per SwiftPM checkout.
  static func sharedPicoSDK(for picoKitRoot: URL) throws -> URL {
    let revisionURL = picoKitRoot.appendingPathComponent("Vendor/pico-sdk.revision")
    guard FileManager.default.fileExists(atPath: revisionURL.path) else {
      // Compatibility for a PicoKit checkout from before shared SDK support.
      let legacy = picoKitRoot.appendingPathComponent("Vendor/pico-sdk")
      guard
        FileManager.default.fileExists(atPath: legacy.appendingPathComponent("CMakeLists.txt").path)
      else {
        throw CLIError.message(
          "PicoKit does not declare a Pico SDK revision. Update PicoKit, or set picoSDKPath in swiftpico.json."
        )
      }
      return legacy
    }

    let revision = try String(contentsOf: revisionURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
      throw CLIError.message("invalid Pico SDK revision in \(revisionURL.path)")
    }

    let root = sharedPicoSDKCacheRoot()
    let sdk = root.appendingPathComponent("pico-sdk/\(revision)", isDirectory: true)
    if FileManager.default.fileExists(atPath: sdk.appendingPathComponent("CMakeLists.txt").path) {
      return sdk
    }

    try FileManager.default.createDirectory(
      at: sdk.deletingLastPathComponent(), withIntermediateDirectories: true)
    let temporary = sdk.deletingLastPathComponent()
      .appendingPathComponent(".\(revision).\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    print("  Downloading shared Pico SDK \(revision.prefix(12))…")
    try runProcess([
      "git", "clone", "--filter=blob:none", "https://github.com/raspberrypi/pico-sdk.git",
      temporary.path,
    ])
    try runProcess(["git", "-C", temporary.path, "checkout", "--detach", revision])
    try runProcess(["git", "-C", temporary.path, "submodule", "update", "--init", "--recursive"])
    guard
      FileManager.default.fileExists(
        atPath: temporary.appendingPathComponent("CMakeLists.txt").path)
    else {
      throw CLIError.message("shared Pico SDK checkout did not contain CMakeLists.txt")
    }
    do {
      try FileManager.default.moveItem(at: temporary, to: sdk)
    } catch
      where FileManager.default.fileExists(
        atPath: sdk.appendingPathComponent("CMakeLists.txt").path)
    {
      // Another SwiftPico process won the race and created the same cache entry.
    }
    return sdk
  }

  static func sharedPicoSDKCacheRoot() -> URL {
    let environment = ProcessInfo.processInfo.environment
    if let path = environment["SWIFTPICO_CACHE_DIR"], !path.isEmpty {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    #if os(macOS)
      return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SwiftPico", isDirectory: true)
    #else
      if let path = environment["XDG_CACHE_HOME"], !path.isEmpty {
        return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(
          "swiftpico", isDirectory: true)
      }
      return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/swiftpico", isDirectory: true)
    #endif
  }
}
