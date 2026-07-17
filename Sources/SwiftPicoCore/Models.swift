import Foundation

struct PicoKitConfig: Codable {
  /// Missing means the legacy v0 format. New files always encode schema 1.
  var schemaVersion: Int? = SwiftPicoVersion.projectSchema
  var board: String
  var firmwareDirectory: String? = nil
  var picoSDKPath: String? = nil
  var picoKitPath: String? = nil
  var picoKitURL: String? = nil
  var picoKitVersion: String? = nil
  var picotool: String? = nil
  var swiftSDK: String? = nil
  /// Defaults to true for older project files that do not contain this key.
  var initializeUSBInterfaceAtStart: Bool? = nil
  var product: String? = nil
  var configuration = "release"
  var uf2: String? = nil
  var openOCD = "openocd"
  var openOCDConfig: [String] = []

  var initializesUSBInterfaceAtStart: Bool {
    initializeUSBInterfaceAtStart ?? true
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion, board, firmwareDirectory, picoSDKPath, picoKitPath, picoKitURL
    case picoKitVersion, picotool, swiftSDK, product, configuration, uf2
    case openOCD, openOCDConfig
    case initializeUSBInterfaceAtStart = "initialize_usb_interface_at_start"
  }

  init(
    schemaVersion: Int? = SwiftPicoVersion.projectSchema,
    board: String,
    firmwareDirectory: String? = nil,
    picoSDKPath: String? = nil,
    picoKitPath: String? = nil,
    picoKitURL: String? = nil,
    picoKitVersion: String? = nil,
    picotool: String? = nil,
    swiftSDK: String? = nil,
    initializeUSBInterfaceAtStart: Bool? = nil,
    product: String? = nil,
    configuration: String = "release",
    uf2: String? = nil,
    openOCD: String = "openocd",
    openOCDConfig: [String] = []
  ) {
    self.schemaVersion = schemaVersion
    self.board = board
    self.firmwareDirectory = firmwareDirectory
    self.picoSDKPath = picoSDKPath
    self.picoKitPath = picoKitPath
    self.picoKitURL = picoKitURL
    self.picoKitVersion = picoKitVersion
    self.picotool = picotool
    self.swiftSDK = swiftSDK
    self.initializeUSBInterfaceAtStart = initializeUSBInterfaceAtStart
    self.product = product
    self.configuration = configuration
    self.uf2 = uf2
    self.openOCD = openOCD
    self.openOCDConfig = openOCDConfig
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
    board = try values.decode(String.self, forKey: .board)
    firmwareDirectory = try values.decodeIfPresent(String.self, forKey: .firmwareDirectory)
    picoSDKPath = try values.decodeIfPresent(String.self, forKey: .picoSDKPath)
    picoKitPath = try values.decodeIfPresent(String.self, forKey: .picoKitPath)
    picoKitURL = try values.decodeIfPresent(String.self, forKey: .picoKitURL)
    picoKitVersion = try values.decodeIfPresent(String.self, forKey: .picoKitVersion)
    picotool = try values.decodeIfPresent(String.self, forKey: .picotool)
    swiftSDK = try values.decodeIfPresent(String.self, forKey: .swiftSDK)
    initializeUSBInterfaceAtStart = try values.decodeIfPresent(
      Bool.self, forKey: .initializeUSBInterfaceAtStart)
    product = try values.decodeIfPresent(String.self, forKey: .product)
    configuration = try values.decodeIfPresent(String.self, forKey: .configuration) ?? "release"
    uf2 = try values.decodeIfPresent(String.self, forKey: .uf2)
    openOCD = try values.decodeIfPresent(String.self, forKey: .openOCD) ?? "openocd"
    openOCDConfig = try values.decodeIfPresent([String].self, forKey: .openOCDConfig) ?? []
  }
}

struct FirmwareBuildState: Codable, Equatable {
  let swiftPicoVersion: String
  let picoKitVersion: String
}

public enum ProjectSchemaMigration: Equatable {
  case legacyV0
  case current

  public static func required(for schemaVersion: Int?) throws -> Self {
    guard let schemaVersion else { return .legacyV0 }
    guard schemaVersion == SwiftPicoVersion.projectSchema else {
      throw ProjectSchemaError.unsupported(schemaVersion)
    }
    return .current
  }
}

public enum ProjectSchemaError: LocalizedError, Equatable {
  case unsupported(Int)
  public var errorDescription: String? {
    switch self {
    case .unsupported(let value):
      "unsupported swiftpico.json schemaVersion \(value); update SwiftPico before opening this project"
    }
  }
}

public enum PathSafety {
  public static func isSafeDependencyPath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/") else { return false }
    return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
  }
}

public struct BuildStateFingerprint: Codable, Equatable {
  public let swiftPicoVersion: String
  public let picoKitVersion: String
  public init(swiftPicoVersion: String, picoKitVersion: String) {
    self.swiftPicoVersion = swiftPicoVersion
    self.picoKitVersion = picoKitVersion
  }
  public func invalidates(_ existing: BuildStateFingerprint?) -> Bool { existing != self }
}

public enum FlashStrategy: Equatable, Sendable {
  case requestedVolume, mountedBootVolume, serialReset, picotool, unavailable

  public static func select(
    requestedVolume: Bool, bootVolume: Bool, serialDeviceCount: Int, picotoolAvailable: Bool
  ) -> Self {
    if requestedVolume { return .requestedVolume }
    if bootVolume { return .mountedBootVolume }
    if serialDeviceCount == 1 { return .serialReset }
    if picotoolAvailable { return .picotool }
    return .unavailable
  }
}

enum SerialMonitorError: LocalizedError, Equatable {
  case noDevice
  case multipleDevices([String])
  case invalidBaud(String)

  var errorDescription: String? {
    switch self {
    case .noDevice:
      "No serial device found. Connect the Pico, then run 'swiftpico devices'."
    case .multipleDevices(let devices):
      "Multiple serial devices found. Pass --device <path>:\n\(devices.map { "  \($0)" }.joined(separator: "\n"))"
    case .invalidBaud(let value):
      "Invalid serial baud rate '\(value)'. Use a positive rate up to 4,000,000 (default: 115200)."
    }
  }
}

enum SerialMonitorConfiguration {
  static func selectDevice(explicit: String?, detected: [String]) throws -> String {
    if let explicit, !explicit.isEmpty { return explicit }
    guard !detected.isEmpty else { throw SerialMonitorError.noDevice }
    guard detected.count == 1 else { throw SerialMonitorError.multipleDevices(detected) }
    return detected[0]
  }

  static func reconnectCandidate(explicit: String?, detected: [String]) -> String? {
    if let explicit { return detected.contains(explicit) ? explicit : nil }
    return detected.count == 1 ? detected[0] : nil
  }

  static func baud(from rawValue: String) throws -> UInt32 {
    guard let value = UInt32(rawValue), value > 0, value <= 4_000_000 else {
      throw SerialMonitorError.invalidBaud(rawValue)
    }
    return value
  }
}

struct ProjectContext {
  let root: URL
  let config: PicoKitConfig

  func url(for path: String) -> URL {
    path.hasPrefix("/")
      ? URL(fileURLWithPath: path)
      : root.appendingPathComponent(path).standardizedFileURL
  }
}

enum CLIError: LocalizedError {
  case usage
  case message(String)
  var errorDescription: String? {
    switch self {
    case .usage: SwiftPicoCommand.usage
    case .message(let text): text
    }
  }
}

struct StageFailure: LocalizedError {
  let stage: String
  let subject: String
  let recovery: String
  let underlying: Error

  var errorDescription: String? {
    "stage '\(stage)' failed for \(subject): \(underlying.localizedDescription)\nRecovery: \(recovery)"
  }
}

extension JSONEncoder {
  static var pretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
