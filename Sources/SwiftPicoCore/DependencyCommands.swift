import Dispatch
import Foundation

#if os(macOS)
  import Darwin
#else
  import Glibc
#endif

extension SwiftPicoCommand {
  static func addLibrary(_ arguments: [String]) throws {
    guard let kind = arguments.first, ["swift", "c", "cpp", "cxx"].contains(kind) else {
      throw CLIError.message("usage: swiftpico add swift|c [options]")
    }
    let project = try context(arguments)
    let libraryArguments = Array(arguments.dropFirst())

    switch kind {
    case "swift":
      try addSwiftLibrary(libraryArguments, project: project)
    default:
      try addCLibrary(libraryArguments, language: kind == "c" ? .c : .cpp, project: project)
    }
  }

  static func addSwiftLibrary(_ arguments: [String], project: ProjectContext) throws {
    guard let url = option("--url", in: arguments),
      let version = option("--from", in: arguments),
      let package = option("--package", in: arguments),
      let product = option("--product", in: arguments)
    else {
      throw CLIError.message(
        "swift library requires --url URL --from VERSION --package PACKAGE --product PRODUCT")
    }
    let target = option("--target", in: arguments) ?? product
    guard isCMakeIdentifier(product), isCMakeIdentifier(target) else {
      throw CLIError.message(
        "--product and --target must contain only letters, numbers, or underscores")
    }

    let manifestURL = project.root.appendingPathComponent("Package.swift")
    var manifest = try String(contentsOf: manifestURL, encoding: .utf8)
    let dependency =
      ".package(name: \(swiftStringLiteral(package)), url: \(swiftStringLiteral(url)), exact: \(swiftStringLiteral(version)))"
    let productDependency =
      ".product(name: \(swiftStringLiteral(product)), package: \(swiftStringLiteral(package)))"
    if !manifest.contains(dependency) {
      manifest = try addSwiftPMDependency(
        dependency, productDependency: productDependency, to: manifest)
      try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    try DependencySupport.addSwiftDependency(
      root: project.root, name: product, url: url, revision: version,
      package: package, product: product, target: target
    )
    if !arguments.contains("--skip-resolve") {
      try runProcess(["swift", "package", "resolve"], currentDirectory: project.root)
      try resolveDependencies(project)
    }
    print(
      "Added Swift library \(product). Import \(product) from Sources/ and run swiftpico build.")
  }

  static func addCLibrary(
    _ arguments: [String],
    language: FirmwareDependency.Language,
    project: ProjectContext
  ) throws {
    guard let url = option("--url", in: arguments),
      let tag = option("--tag", in: arguments),
      let target = option("--target", in: arguments)
    else {
      throw CLIError.message("C/C++ library requires --url URL --tag TAG --target CMAKE_TARGET")
    }
    guard isCMakeTargetName(target) else {
      throw CLIError.message("--target must be a CMake target name, optionally with :: namespaces")
    }
    let name =
      option("--name", in: arguments)
      ?? target.replacingOccurrences(of: "::", with: "_").lowercased()
    guard isCMakeIdentifier(name) else {
      throw CLIError.message("--name must contain only letters, numbers, or underscores")
    }
    try DependencySupport.addCMakeDependency(
      root: project.root, name: name, language: language,
      url: url, revision: tag, target: target
    )
    if !arguments.contains("--skip-resolve") { try resolveDependencies(project) }
    print(
      "Added C/C++ library target \(target). Its exact commit is recorded by 'swiftpico dependencies resolve'."
    )
  }

  static func dependencies(_ arguments: [String]) throws {
    guard let action = arguments.first else {
      throw CLIError.message(
        "usage: swiftpico dependencies resolve|generate|remove|update|migrate|show")
    }
    let project = try context(Array(arguments.dropFirst()))
    switch action {
    case "resolve":
      print("Resolving Swift package dependencies in \(project.root.path)…")
      try runProcess(["swift", "package", "resolve"], currentDirectory: project.root)
      print("Resolving PicoKit and firmware dependency revisions…")
      try resolveDependencies(project)
      print("Writing dependencies.lock and generated CMake…")
      print("Resolved dependencies and regenerated Firmware/Generated/Dependencies.cmake.")
    case "generate":
      try DependencySupport.generateFromLock(root: project.root)
      print("Regenerated Firmware/Generated/Dependencies.cmake from the lock file.")
    case "remove":
      guard arguments.count >= 2, !arguments[1].hasPrefix("--") else {
        throw CLIError.message("usage: swiftpico dependencies remove NAME")
      }
      let removed = try DependencySupport.remove(root: project.root, name: arguments[1])
      if removed.language == .swift, let package = removed.package, let product = removed.product {
        try removeSwiftPMDependency(package: package, product: product, projectRoot: project.root)
      }
      print("Removed \(arguments[1]); run 'swiftpico dependencies resolve' before building.")
    case "update":
      guard arguments.count >= 2, !arguments[1].hasPrefix("--"),
        let revision = option("--revision", in: arguments)
      else {
        throw CLIError.message("usage: swiftpico dependencies update NAME --revision REVISION")
      }
      let old = try DependencySupport.update(
        root: project.root, name: arguments[1], revision: revision)
      if old.language == .swift, let package = old.package {
        let packageURL = project.root.appendingPathComponent("Package.swift")
        var manifest = try String(contentsOf: packageURL, encoding: .utf8)
        manifest = manifest.replacingOccurrences(
          of:
            ".package(name: \(swiftStringLiteral(package)), url: \(swiftStringLiteral(old.repositoryURL)), exact: \(swiftStringLiteral(old.revision)))",
          with:
            ".package(name: \(swiftStringLiteral(package)), url: \(swiftStringLiteral(old.repositoryURL)), exact: \(swiftStringLiteral(revision)))"
        )
        try manifest.write(to: packageURL, atomically: true, encoding: .utf8)
      }
      print("Updated \(arguments[1]) intent to \(revision); run 'swiftpico dependencies resolve'.")
    case "migrate":
      try DependencySupport.migrate(root: project.root)
      print("Created the v0.2 dependency and application interop structure.")
    case "show":
      let manifest = try DependencySupport.loadManifest(root: project.root)
      if manifest.dependencies.isEmpty { print("No external firmware dependencies.") }
      for dependency in manifest.dependencies {
        print(
          "\(dependency.name): \(dependency.language.rawValue) \(dependency.integration.rawValue) @ \(dependency.revision)"
        )
      }
    default:
      throw CLIError.message("unknown dependencies action '\(action)'")
    }
  }

  static func resolveDependencies(_ project: ProjectContext) throws {
    _ = try DependencySupport.resolve(
      root: project.root,
      picoKitURL: project.config.picoKitURL ?? Self.defaultPicoKitURL,
      picoKitVersion: project.config.picoKitVersion ?? Self.offlinePicoKitVersion,
      picoKitPath: project.config.picoKitPath
    )
  }

  static func removeSwiftPMDependency(package: String, product: String, projectRoot: URL) throws {
    let url = projectRoot.appendingPathComponent("Package.swift")
    let manifest = try String(contentsOf: url, encoding: .utf8)
    let packagePrefix = ".package(name: \(swiftStringLiteral(package)),"
    let productEntry =
      ".product(name: \(swiftStringLiteral(product)), package: \(swiftStringLiteral(package)))"
    let filtered = manifest.split(separator: "\n", omittingEmptySubsequences: false).filter {
      !$0.contains(packagePrefix) && !$0.contains(productEntry)
    }.joined(separator: "\n")
    try filtered.write(to: url, atomically: true, encoding: .utf8)
  }

}
