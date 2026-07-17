import Foundation

extension SwiftPicoCommand {
  static func canonicalBoard(_ value: String) throws -> PicoBoard {
    guard let board = PicoBoard(configurationName: value) else {
      throw CLIError.message("unsupported board '\(value)'. Choose: pico, pico_w, pico2, pico2_w")
    }
    return board
  }

  static func firmwareTargetName(_ product: String) -> String {
    let safe = product.unicodeScalars.map {
      CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" ? String($0) : "_"
    }.joined()
    return safe.isEmpty ? "PicoKitFirmware" : safe
  }

  static func swiftTargetName(_ product: String) -> String {
    let safe = product.unicodeScalars.map {
      CharacterSet.alphanumerics.contains($0) || $0 == "_" ? String($0) : "_"
    }.joined()
    guard !safe.isEmpty else { return "PicoApp" }
    return safe.first?.isNumber == true ? "Pico\(safe)" : safe
  }

  static func swiftStringLiteral(_ value: String) -> String {
    String(reflecting: value)
  }

  static func projectManifest(
    name: String, target: String, picoKitURL: String, picoKitVersion: String, picoKitPath: String?
  ) -> String {
    let packageName = swiftStringLiteral(name)
    let swiftName = swiftStringLiteral(swiftTargetName(target))
    let picoKitDependency: String
    if let picoKitPath {
      picoKitDependency = ".package(path: \(swiftStringLiteral(picoKitPath)))"
    } else {
      picoKitDependency =
        ".package(url: \(swiftStringLiteral(picoKitURL)), exact: \(swiftStringLiteral(picoKitVersion)))"
    }
    return """
      // swift-tools-version: 6.0
      import PackageDescription

      let package = Package(
          name: \(packageName),
          platforms: [.macOS(.v13)],
          dependencies: [
              \(picoKitDependency)
          ],
          targets: [
              .executableTarget(
                  name: \(swiftName),
                  dependencies: [.product(name: "PicoKit", package: "PicoKit")]
              )
          ]
      )
      """
  }

  static func addSwiftPMDependency(
    _ dependency: String, productDependency: String, to manifest: String
  ) throws -> String {
    guard let dependenciesRange = manifest.range(of: "dependencies: [") else {
      throw CLIError.message(
        "Package.swift is not a SwiftPico-generated manifest; add the Swift package dependency and product manually."
      )
    }

    var updated = manifest
    updated.insert(contentsOf: "\n        \(dependency),", at: dependenciesRange.upperBound)
    guard let targetsRange = updated.range(of: "targets: ["),
      let refreshedTargetRange = updated.range(
        of: "dependencies: [", range: targetsRange.upperBound..<updated.endIndex),
      let refreshedClosingBracket = updated.range(
        of: "]", range: refreshedTargetRange.upperBound..<updated.endIndex)
    else {
      throw CLIError.message("could not update target dependencies in Package.swift")
    }
    updated.insert(
      contentsOf: "\n                    \(productDependency),",
      at: refreshedClosingBracket.lowerBound)
    return updated
  }

  static func appendDependencyBlock(_ block: String, to file: URL) throws {
    let marker = "# Added by swiftpico add"
    let entry = "\(marker)\n\(block)\n"
    if FileManager.default.fileExists(atPath: file.path) {
      let existing = try String(contentsOf: file, encoding: .utf8)
      guard !existing.contains(entry) else {
        print("Library is already present in \(file.path)")
        return
      }
      try (existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + entry).write(
        to: file, atomically: true, encoding: .utf8)
    } else {
      try entry.write(to: file, atomically: true, encoding: .utf8)
    }
  }

  static func isCMakeIdentifier(_ value: String) -> Bool {
    !value.isEmpty
      && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
  }

  static func isCMakeTargetName(_ value: String) -> Bool {
    let components = value.split(separator: ":", omittingEmptySubsequences: false)
    guard !components.isEmpty else { return false }
    var index = 0
    while index < components.count {
      guard !components[index].isEmpty, isCMakeIdentifier(String(components[index])) else {
        return false
      }
      index += 1
      if index < components.count {
        guard index + 1 < components.count, components[index].isEmpty else { return false }
        index += 1
      }
    }
    return true
  }
}
