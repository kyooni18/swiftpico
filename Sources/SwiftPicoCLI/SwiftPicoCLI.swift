import Foundation
import Dispatch
#if os(macOS)
import Darwin
#else
import Glibc
#endif

@main
struct SwiftPicoCommand {
    private static let defaultPicoKitURL = "https://github.com/kyooni18/PicoKit.git"
    private static let offlinePicoKitVersion = "0.2.5"
    private static let releaseVersion = "0.2.6"

    private static let firmwareProjectManifest = """
    cmake_minimum_required(VERSION 3.29)

    if(NOT DEFINED PICOKIT_ROOT)
        message(FATAL_ERROR "PICOKIT_ROOT must point to the resolved PicoKit package checkout")
    endif()

    set(PICO_SDK_PATH "${PICOKIT_ROOT}/Vendor/pico-sdk" CACHE PATH "Pico SDK path")
    include("${PICO_SDK_PATH}/external/pico_sdk_import.cmake")
    project(PicoKitFirmware LANGUAGES C CXX ASM)
    set(PICOKIT_PROJECT_INITIALIZED YES)
    include("${PICOKIT_ROOT}/Firmware/CMakeLists.txt")

    # USB configuration is supplied by `swiftpico build` from
    # initialize_usb_interface_at_start in swiftpico.json.
    """

    private static let projectRunner = """
    #!/bin/sh
    exec "${SWIFTPICO:-swiftpico}" "$@"
    """

    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("swiftpico: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else { throw CLIError.usage }
        let args = Array(arguments.dropFirst())
        try validateArguments(command: command, arguments: args)
        switch command {
        case "help", "--help", "-h": print(usage)
        case "init", "new": try initialise(args)
        case "add": try addLibrary(args)
        case "dependencies", "deps": try dependencies(args)
        case "build", "b": try build(args)
        case "flash", "upload", "f": try flash(args)
        case "make", "m": try build(args); try flash(args)
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

    // MARK: - init / new

    private static func initialise(_ arguments: [String]) throws {
        let requestedBoard = option("--board", in: arguments) ?? "pico"
        guard let picoBoard = PicoBoard(configurationName: requestedBoard) else {
            throw CLIError.message("unsupported board '\(requestedBoard)'. Choose: pico, pico_w, pico2, pico2_w")
        }
        let board = picoBoard.rawValue
        let name = option("--name", in: arguments) ?? "PicoApp"
        let template = option("--template", in: arguments) ?? "blink"
        guard availableTemplates.contains(template) else {
                throw CLIError.message("unknown template '\(template)'. Run 'swiftpico template' to list supported templates.")
        }
        let force = arguments.contains("--force")
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let picoKitURL = option("--pico-kit-url", in: arguments) ?? Self.defaultPicoKitURL
        let picoKitPath = option("--pico-kit-path", in: arguments).map {
            URL(fileURLWithPath: $0, relativeTo: currentDirectory).standardizedFileURL
        }
        let skipResolve = arguments.contains("--skip-resolve")
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
        try JSONEncoder.pretty.encode(config).write(to: configURL)

        let manifest = projectManifest(
            name: name,
            target: target,
            picoKitURL: picoKitURL,
            picoKitVersion: picoKitVersion,
            picoKitPath: picoKitPath?.path
        )
        try manifest.write(to: projectRoot.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

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
        try DependencySupport.initializeProject(at: projectRoot)

        let runner = projectRoot.appendingPathComponent("swiftpico")
        try projectRunner.write(to: runner, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runner.path)

        try """
        .build/
        Firmware/build/
        Firmware/Dependencies.local.cmake
        *.uf2
        """.write(to: projectRoot.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        if !skipResolve {
            if picoKitPath == nil {
                _ = try installPicoKitDependency(projectRoot: projectRoot, config: config)
            } else {
                try runProcess(["swift", "package", "resolve"], currentDirectory: projectRoot)
            }
            _ = try DependencySupport.resolve(
                root: projectRoot,
                picoKitURL: picoKitURL,
                picoKitVersion: picoKitVersion,
                picoKitPath: picoKitPath?.path
            )
        } else if picoKitPath != nil {
            _ = try DependencySupport.resolve(
                root: projectRoot,
                picoKitURL: picoKitURL,
                picoKitVersion: picoKitVersion,
                picoKitPath: picoKitPath?.path
            )
        }

        print("""
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

    // MARK: - external libraries

    private static func addLibrary(_ arguments: [String]) throws {
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

    private static func addSwiftLibrary(_ arguments: [String], project: ProjectContext) throws {
        guard let url = option("--url", in: arguments),
              let version = option("--from", in: arguments),
              let package = option("--package", in: arguments),
              let product = option("--product", in: arguments) else {
            throw CLIError.message("swift library requires --url URL --from VERSION --package PACKAGE --product PRODUCT")
        }
        let target = option("--target", in: arguments) ?? product
        guard isCMakeIdentifier(product), isCMakeIdentifier(target) else {
            throw CLIError.message("--product and --target must contain only letters, numbers, or underscores")
        }

        let manifestURL = project.root.appendingPathComponent("Package.swift")
        var manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let dependency = ".package(name: \(swiftStringLiteral(package)), url: \(swiftStringLiteral(url)), exact: \(swiftStringLiteral(version)))"
        let productDependency = ".product(name: \(swiftStringLiteral(product)), package: \(swiftStringLiteral(package)))"
        if !manifest.contains(dependency) {
            manifest = try addSwiftPMDependency(dependency, productDependency: productDependency, to: manifest)
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
        print("Added Swift library \(product). Import \(product) from Sources/ and run swiftpico build.")
    }

    private static func addCLibrary(
        _ arguments: [String],
        language: FirmwareDependency.Language,
        project: ProjectContext
    ) throws {
        guard let url = option("--url", in: arguments),
              let tag = option("--tag", in: arguments),
              let target = option("--target", in: arguments) else {
            throw CLIError.message("C/C++ library requires --url URL --tag TAG --target CMAKE_TARGET")
        }
        guard isCMakeTargetName(target) else {
            throw CLIError.message("--target must be a CMake target name, optionally with :: namespaces")
        }
        let name = option("--name", in: arguments) ?? target.replacingOccurrences(of: "::", with: "_").lowercased()
        guard isCMakeIdentifier(name) else {
            throw CLIError.message("--name must contain only letters, numbers, or underscores")
        }
        try DependencySupport.addCMakeDependency(
            root: project.root, name: name, language: language,
            url: url, revision: tag, target: target
        )
        if !arguments.contains("--skip-resolve") { try resolveDependencies(project) }
        print("Added C/C++ library target \(target). Its exact commit is recorded by 'swiftpico dependencies resolve'.")
    }

    private static func dependencies(_ arguments: [String]) throws {
        guard let action = arguments.first else {
            throw CLIError.message("usage: swiftpico dependencies resolve|generate|remove|update|migrate|show")
        }
        let project = try context(Array(arguments.dropFirst()))
        switch action {
        case "resolve":
            try runProcess(["swift", "package", "resolve"], currentDirectory: project.root)
            try resolveDependencies(project)
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
                  let revision = option("--revision", in: arguments) else {
                throw CLIError.message("usage: swiftpico dependencies update NAME --revision REVISION")
            }
            let old = try DependencySupport.update(root: project.root, name: arguments[1], revision: revision)
            if old.language == .swift, let package = old.package {
                let packageURL = project.root.appendingPathComponent("Package.swift")
                var manifest = try String(contentsOf: packageURL, encoding: .utf8)
                manifest = manifest.replacingOccurrences(
                    of: ".package(name: \(swiftStringLiteral(package)), url: \(swiftStringLiteral(old.repositoryURL)), exact: \(swiftStringLiteral(old.revision)))",
                    with: ".package(name: \(swiftStringLiteral(package)), url: \(swiftStringLiteral(old.repositoryURL)), exact: \(swiftStringLiteral(revision)))"
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
            for dependency in manifest.dependencies { print("\(dependency.name): \(dependency.language.rawValue) \(dependency.integration.rawValue) @ \(dependency.revision)") }
        default:
            throw CLIError.message("unknown dependencies action '\(action)'")
        }
    }

    private static func resolveDependencies(_ project: ProjectContext) throws {
        _ = try DependencySupport.resolve(
            root: project.root,
            picoKitURL: project.config.picoKitURL ?? Self.defaultPicoKitURL,
            picoKitVersion: project.config.picoKitVersion ?? Self.offlinePicoKitVersion,
            picoKitPath: project.config.picoKitPath
        )
    }

    private static func removeSwiftPMDependency(package: String, product: String, projectRoot: URL) throws {
        let url = projectRoot.appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: url, encoding: .utf8)
        let packagePrefix = ".package(name: \(swiftStringLiteral(package)),"
        let productEntry = ".product(name: \(swiftStringLiteral(product)), package: \(swiftStringLiteral(package)))"
        let filtered = manifest.split(separator: "\n", omittingEmptySubsequences: false).filter {
            !$0.contains(packagePrefix) && !$0.contains(productEntry)
        }.joined(separator: "\n")
        try filtered.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - build

    private static func build(_ arguments: [String]) throws {
        let project = try context(arguments)
        if FileManager.default.fileExists(atPath: project.root.appendingPathComponent(DependencySupport.manifestPath).path) {
            try DependencySupport.generateFromLock(root: project.root)
        }
        let config = project.config
        if let firmwareDirectory = config.firmwareDirectory {
            let configuration = option("--configuration", in: arguments) ?? config.configuration
            guard ["debug", "release"].contains(configuration.lowercased()) else {
                throw CLIError.message("configuration must be 'debug' or 'release', not '\(configuration)'")
            }
            guard isToolAvailable("arm-none-eabi-gcc") || ProcessInfo.processInfo.environment["PICO_TOOLCHAIN_PATH"] != nil else {
                throw CLIError.message("arm-none-eabi-gcc was not found. Install the Pico SDK ARM toolchain or set PICO_TOOLCHAIN_PATH, then run 'swiftpico doctor'.")
            }
            let firmwareURL = project.url(for: firmwareDirectory)
            let buildDirectory = firmwareURL.appendingPathComponent("build", isDirectory: true)
            var configure = [
                "cmake", "-S", firmwareURL.path, "-B", buildDirectory.path,
                "-G", "Ninja", "-DCMAKE_BUILD_TYPE=\(configuration.capitalized)", "-DPICO_BOARD=\(try canonicalBoard(config.board).cmakeName)",
            ]
            let product = firmwareTargetName(option("--product", in: arguments) ?? config.product ?? "PicoKitFirmware")
            let sourceName = option("--product", in: arguments) ?? config.product ?? "PicoKitFirmware"
            configure += ["-DPICOKIT_PRODUCT=\(product)", "-DPICOKIT_SOURCE=\(project.root.appendingPathComponent("Sources/\(sourceName)/main.swift").path)"]
            configure.append("-DPICOKIT_ENABLE_USB=\(config.initializesUSBInterfaceAtStart ? "ON" : "OFF")")
            let picoKitRoot = try resolvePicoKitRoot(project: project, config: config)
            let picoKitVersion = persistedPicoKitVersion(project: project, fallback: config.picoKitVersion)
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
            try runProcess(configure)
            let build = ["cmake", "--build", buildDirectory.path]
            print("Building firmware: \(build.joined(separator: " "))")
            try runProcess(build)
            try writeFirmwareBuildState(buildState, to: project.root.appendingPathComponent(".swiftpico/firmware-build.json"))
            print("Firmware build succeeded.")
            return
        }
        guard let sdk = option("--swift-sdk", in: arguments) ?? config.swiftSDK else {
            throw CLIError.message("no Swift Embedded SDK is configured. Install one, then set 'swiftSDK' in swiftpico.json or pass --swift-sdk <id>. Refusing to build a host executable that cannot be flashed to \(config.board).")
        }
        var command = ["swift", "build", "-c", option("--configuration", in: arguments) ?? config.configuration]
        command += ["--swift-sdk", sdk]
        if let product = option("--product", in: arguments) ?? config.product { command += ["--product", product] }
        if arguments.contains("--verbose") { command += ["--verbose"] }
        print("Building: \(command.joined(separator: " "))")
        try runProcess(command, currentDirectory: project.root)
        print("Build succeeded.")
    }

    // MARK: - clean

    private static func clean(_ arguments: [String]) throws {
        let project = try context(arguments)
        let config = project.config
        print("Cleaning build artifacts...")
        if let firmwareDirectory = config.firmwareDirectory {
            let buildDirectory = project.url(for: firmwareDirectory)
                .appendingPathComponent("build", isDirectory: true)
            if FileManager.default.fileExists(atPath: buildDirectory.path) {
                try FileManager.default.removeItem(at: buildDirectory)
            }
        } else {
            try runProcess(["swift", "package", "clean"], currentDirectory: project.root)
        }
        print("Clean complete.")
    }

    // MARK: - flash / upload

    private static func flash(_ arguments: [String]) throws {
        let project = try context(arguments)
        let config = project.config
        let uf2 = option("--uf2", in: arguments) ?? config.uf2
        guard let uf2 else { throw CLIError.message("set 'uf2' in swiftpico.json or pass --uf2 path/to/app.uf2") }
        let source = project.url(for: uf2)
        guard FileManager.default.fileExists(atPath: source.path) else { throw CLIError.message("UF2 file not found: \(source.path)") }

        if let requestedVolume = option("--volume", in: arguments).map({ project.url(for: $0) }) {
            try copyUF2ToVolume(source, volume: requestedVolume)
            ejectBootVolume(requestedVolume)
            print("Flashed \(source.lastPathComponent) to \(requestedVolume.path)")
            print("Ejected the BOOTSEL volume; Pico is restarting.")
            return
        }

        let requestedPicotool = option("--picotool", in: arguments).map { project.url(for: $0).path }
        var picotoolFailed = false
        if let picotool = requestedPicotool ?? findPicotool(config, projectRoot: project.root) {
            print("Flashing \(source.lastPathComponent) over USB with picotool…")
            do {
                // `-f` asks picotool to reboot automatically after loading,
                // which races USB re-enumeration on some RP2350 boards. `-F`
                // keeps BOOTSEL available until this explicit application
                // reboot completes the transfer deterministically.
                try runProcess([picotool, "load", "-F", source.path])
                try runProcess([picotool, "reboot", "--application"])
                print("Flashed \(source.lastPathComponent) over USB.")
                return
            } catch {
                picotoolFailed = true
                print("picotool could not enter BOOTSEL; falling back to USB serial reset…")
            }
        }

        if let mountedVolume = findBootVolume() {
            try copyUF2ToVolume(source, volume: mountedVolume)
            ejectBootVolume(mountedVolume)
            print("Flashed \(source.lastPathComponent) to \(mountedVolume.path)")
            print("Ejected the BOOTSEL volume; Pico is restarting.")
            return
        }

        // USB stdio exposes the Pico SDK reset interface even when picotool is
        // not installed. Open the sole CDC device at 1200 baud, wait for the
        // BOOTSEL drive, then use the same UF2 copy path as --volume.
        if serialDevices().count == 1 {
            print("Requesting BOOTSEL over USB serial…")
            try resetToBootloaderOverUSB()
            guard let bootVolume = waitForBootVolume() else {
                throw CLIError.message("Pico did not mount a BOOTSEL volume after the USB serial reset")
            }
            try copyUF2ToVolume(source, volume: bootVolume)
            ejectBootVolume(bootVolume)
            print("Flashed \(source.lastPathComponent) to \(bootVolume.path) over USB.")
            print("Ejected the BOOTSEL volume; Pico is restarting.")
            return
        }

        let picotoolReason = picotoolFailed
            ? "picotool could not access an RP-series device"
            : "picotool was not found"
        throw CLIError.message("\(picotoolReason), and no single USB serial device is available for the automatic BOOTSEL reset. Connect the Pico with a data cable while holding BOOTSEL, or pass --volume /Volumes/RPI-RP2 to use an already-mounted BOOTSEL volume.")
    }

    // MARK: - debug

    private static func debug(_ arguments: [String]) throws {
        let project = try context(arguments)
        let config = project.config
        let openOCD = option("--openocd", in: arguments) ?? config.openOCD
        let files = config.openOCDConfig
        guard !files.isEmpty else { throw CLIError.message("set 'openOCDConfig' in swiftpico.json (for example interface/cmsis-dap.cfg,target/rp2040.cfg)") }
        var command = [openOCD] + files.flatMap { ["-f", $0] }
        if let target = option("--target", in: arguments) {
            command += ["-c", "target remote \(target)"]
        }
        print("Starting OpenOCD: \(command.joined(separator: " "))")
        try runProcess(command, currentDirectory: project.root)
    }

    // MARK: - monitor

    private static func monitor(_ arguments: [String]) throws {
        let device: String
        if let explicitDevice = option("--device", in: arguments) {
            device = explicitDevice
        } else {
            let devices = serialDevices()
            guard devices.count == 1, let detected = devices.first else {
                let hint = devices.isEmpty
                    ? "No serial device found. Connect the Pico, then run 'swiftpico list'."
                    : "Multiple serial devices found. Pass --device <path>.\n\(devices.map { "  \($0)" }.joined(separator: "\n"))"
                throw CLIError.message(hint)
            }
            device = detected
            print("Using serial device \(device)")
        }
        let baud = option("--baud", in: arguments) ?? "115200"
        #if os(macOS)
        try runProcess(["stty", "-f", device, baud, "raw", "-echo"])
        #else
        try runProcess(["stty", "-F", device, baud, "raw", "-echo"])
        #endif

        let restoreTerminal: (() -> Void)?
        if isatty(STDIN_FILENO) != 0 {
            let savedTerminal = try captureProcessOutput(["stty", "-g"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Character-at-a-time input while retaining signal processing, so
            // Ctrl-C still exits the monitor instead of being sent to firmware.
            try runProcess(["stty", "-icanon", "min", "1", "time", "0", "-echo"])
            restoreTerminal = { try? runProcess(["stty", savedTerminal]) }
        } else {
            restoreTerminal = nil
        }
        defer { restoreTerminal?() }

        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        interrupt.setEventHandler {
            restoreTerminal?()
            Foundation.exit(0)
        }
        interrupt.resume()

        let writer = SerialWriter()
        let inputThread = Thread {
            while true {
                let data = FileHandle.standardInput.availableData
                guard !data.isEmpty else { return }
                writer.write(data)
            }
        }
        inputThread.qualityOfService = .userInteractive
        inputThread.start()

        print("Monitoring \(device) at \(baud) baud. Type to send; press Ctrl-C to stop.")
        reconnect: while true {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: device))
            try writer.open(device)
            while true {
                let data = handle.availableData
                guard !data.isEmpty else {
                    try? handle.close()
                    writer.close()
                    guard arguments.contains("--reconnect") else { return }
                    print("Serial device disconnected; waiting to reconnect…")
                    while !FileManager.default.fileExists(atPath: device) {
                        Thread.sleep(forTimeInterval: 0.25)
                    }
                    continue reconnect
                }
                FileHandle.standardOutput.write(data)
            }
        }
    }

    // MARK: - list

    private static func list() {
        let manager = FileManager.default
        let volumes = manager.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: []) ?? []
        let bootVolumes = volumes.filter {
            isPicoBootVolume($0)
        }
        print("=== Pico Boot Volumes ===")
        print(bootVolumes.isEmpty ? "  none (hold BOOTSEL to enter boot mode)" : bootVolumes.map { "  \($0.path)" }.joined(separator: "\n"))

        print("\n=== Serial Devices ===")
        let devices = serialDevices()
        print(devices.isEmpty ? "  none" : devices.map { "  \($0)" }.joined(separator: "\n"))
    }

    // MARK: - environment diagnostics

    private static func doctor(_ arguments: [String]) throws {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let picoKitRoot = findPicoKitRoot(from: current)
        print("=== PicoKit Environment ===")
        reportTool("swift", arguments: ["--version"])
        reportTool("cmake", arguments: ["--version"])
        reportTool("ninja", arguments: ["--version"])
        reportTool("arm-none-eabi-gcc", arguments: ["--version"])
        if let picoKitRoot {
            let sdk = picoKitRoot.appendingPathComponent("Vendor/pico-sdk")
            let bridge = picoKitRoot.appendingPathComponent("Firmware/PicoKitSDKBridge.c")
            print("  PicoKit:     \(picoKitRoot.path)")
            print("  Pico SDK:    \(FileManager.default.fileExists(atPath: sdk.path) ? sdk.path : "MISSING")")
            print("  SDK bridge:  \(FileManager.default.fileExists(atPath: bridge.path) ? "available" : "MISSING")")
        } else {
            print("  PicoKit:     not found from \(current.path)")
        }
        print("  Boot volumes: \(findBootVolume()?.path ?? "none")")
        print("  Serial:      \(serialDevices().joined(separator: ", ").isEmpty ? "none" : serialDevices().joined(separator: ", "))")
        try reportCallbackProbe()
    }

    private static func reportCallbackProbe() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("swiftpico-callback-probe-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let header = root.appendingPathComponent("Callbacks.h")
        let caller = root.appendingPathComponent("Caller.c")
        let swift = root.appendingPathComponent("Callback.swift")
        try """
        #pragma once
        #include <stdint.h>
        int32_t swiftpico_callback_probe(uint32_t value);
        """.write(to: header, atomically: true, encoding: .utf8)
        try """
        #include "Callbacks.h"
        int32_t call_swiftpico_callback_probe(void) { return swiftpico_callback_probe(42); }
        """.write(to: caller, atomically: true, encoding: .utf8)
        try """
        @_cdecl("swiftpico_callback_probe")
        public func callbackProbe(_ value: UInt32) -> Int32 { Int32(bitPattern: value) }
        """.write(to: swift, atomically: true, encoding: .utf8)

        guard let compiler = swiftCompilerPath() else {
            throw CLIError.message("callback probe failed: real swiftc toolchain binary was not found")
        }
        let swiftObject = root.appendingPathComponent("Callback.o")
        let callerObject = root.appendingPathComponent("Caller.o")
        let linkedObject = root.appendingPathComponent("Linked.o")
        do {
            try runProcess([
                compiler, "-target", "armv6m-none-none-eabi",
                "-enable-experimental-feature", "Embedded", "-wmo",
                "-parse-as-library", "-c", swift.path, "-o", swiftObject.path,
            ], quiet: true)
            try runProcess([
                "arm-none-eabi-gcc", "-mcpu=cortex-m0plus", "-mthumb",
                "-I", root.path, "-c", caller.path, "-o", callerObject.path,
            ], quiet: true)
            try runProcess([
                "arm-none-eabi-ld", "-r", swiftObject.path, callerObject.path,
                "-o", linkedObject.path,
            ], quiet: true)
            let symbols = try captureProcessOutput(["arm-none-eabi-nm", linkedObject.path])
            guard symbols.contains(" T swiftpico_callback_probe") else {
                throw CLIError.message("exported callback symbol was not present")
            }
            print("  C callback:  supported (compiled Swift export and C caller)")
        } catch {
            print("  C callback:  FAILED")
            throw CLIError.message("C-to-Swift callback probe failed: \(error.localizedDescription)")
        }
    }

    private static func reportTool(_ executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let firstLine = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n").first.map(String.init) ?? ""
            print("  \(executable): \(process.terminationStatus == 0 ? firstLine : "MISSING")")
        } catch {
            print("  \(executable): MISSING")
        }
    }

    // MARK: - info

    private static func showInfo(_ arguments: [String]) throws {
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

    // MARK: - Helpers

    private static func canonicalBoard(_ value: String) throws -> PicoBoard {
        guard let board = PicoBoard(configurationName: value) else {
            throw CLIError.message("unsupported board '\(value)'. Choose: pico, pico_w, pico2, pico2_w")
        }
        return board
    }

    private static func firmwareTargetName(_ product: String) -> String {
        let safe = product.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" ? String($0) : "_" }.joined()
        return safe.isEmpty ? "PicoKitFirmware" : safe
    }

    private static func swiftTargetName(_ product: String) -> String {
        let safe = product.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" ? String($0) : "_"
        }.joined()
        guard !safe.isEmpty else { return "PicoApp" }
        return safe.first?.isNumber == true ? "Pico\(safe)" : safe
    }

    private static func swiftStringLiteral(_ value: String) -> String {
        String(reflecting: value)
    }

    private static func projectManifest(name: String, target: String, picoKitURL: String, picoKitVersion: String, picoKitPath: String?) -> String {
        let packageName = swiftStringLiteral(name)
        let swiftName = swiftStringLiteral(swiftTargetName(target))
        let picoKitDependency: String
        if let picoKitPath {
            picoKitDependency = ".package(path: \(swiftStringLiteral(picoKitPath)))"
        } else {
            picoKitDependency = ".package(url: \(swiftStringLiteral(picoKitURL)), exact: \(swiftStringLiteral(picoKitVersion)))"
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

    private static func addSwiftPMDependency(_ dependency: String, productDependency: String, to manifest: String) throws -> String {
        guard let dependenciesRange = manifest.range(of: "dependencies: [") else {
            throw CLIError.message("Package.swift is not a SwiftPico-generated manifest; add the Swift package dependency and product manually.")
        }

        var updated = manifest
        updated.insert(contentsOf: "\n        \(dependency),", at: dependenciesRange.upperBound)
        guard let targetsRange = updated.range(of: "targets: ["),
              let refreshedTargetRange = updated.range(of: "dependencies: [", range: targetsRange.upperBound..<updated.endIndex),
              let refreshedClosingBracket = updated.range(of: "]", range: refreshedTargetRange.upperBound..<updated.endIndex) else {
            throw CLIError.message("could not update target dependencies in Package.swift")
        }
        updated.insert(contentsOf: "\n                    \(productDependency),", at: refreshedClosingBracket.lowerBound)
        return updated
    }

    private static func appendDependencyBlock(_ block: String, to file: URL) throws {
        let marker = "# Added by swiftpico add"
        let entry = "\(marker)\n\(block)\n"
        if FileManager.default.fileExists(atPath: file.path) {
            let existing = try String(contentsOf: file, encoding: .utf8)
            guard !existing.contains(entry) else {
                print("Library is already present in \(file.path)")
                return
            }
            try (existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + entry).write(to: file, atomically: true, encoding: .utf8)
        } else {
            try entry.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private static func isCMakeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
    }

    private static func isCMakeTargetName(_ value: String) -> Bool {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return false }
        var index = 0
        while index < components.count {
            guard !components[index].isEmpty, isCMakeIdentifier(String(components[index])) else { return false }
            index += 1
            if index < components.count {
                guard index + 1 < components.count, components[index].isEmpty else { return false }
                index += 1
            }
        }
        return true
    }

    private static func resolvePicoKitRoot(project: ProjectContext, config: PicoKitConfig) throws -> URL {
        if let configuredPath = config.picoKitPath {
            let root = project.url(for: configuredPath)
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
                throw CLIError.message("PicoKit checkout not found at \(root.path)")
            }
            return root
        }

        let checkout = project.root.appendingPathComponent(".build/checkouts/PicoKit", isDirectory: true)
        if FileManager.default.fileExists(atPath: project.root.appendingPathComponent(DependencySupport.manifestPath).path),
           !FileManager.default.fileExists(atPath: checkout.appendingPathComponent("Package.swift").path) {
            throw CLIError.message("locked PicoKit checkout is missing; run 'swiftpico dependencies resolve' before building")
        }
        return try installPicoKitDependency(projectRoot: project.root, config: config)
    }

    private static func clearPicoKitRepoCache(projectRoot: URL) throws {
        let reposDir = projectRoot.appendingPathComponent(".build/repositories", isDirectory: true)
        guard FileManager.default.fileExists(atPath: reposDir.path) else { return }
        let entries = try FileManager.default.contentsOfDirectory(atPath: reposDir.path)
        for entry in entries where entry.hasPrefix("PicoKit-") {
            try FileManager.default.removeItem(at: reposDir.appendingPathComponent(entry))
        }
    }

    private static func persistedPicoKitVersion(project: ProjectContext, fallback: String?) -> String {
        let configURL = project.root.appendingPathComponent("swiftpico.json")
        let persisted = try? JSONDecoder().decode(PicoKitConfig.self, from: Data(contentsOf: configURL))
        return persisted?.picoKitVersion ?? fallback ?? "local"
    }

    private static func invalidateFirmwareBuildIfNeeded(
        buildDirectory: URL,
        stateURL: URL,
        expected: FirmwareBuildState
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: buildDirectory.path) else { return }

        let existing = try? JSONDecoder().decode(FirmwareBuildState.self, from: Data(contentsOf: stateURL))
        guard existing != expected else { return }

        let previous = existing.map {
            "SwiftPico \($0.swiftPicoVersion), PicoKit \($0.picoKitVersion)"
        } ?? "an unknown earlier build"
        print("Build versions changed (\(previous) → SwiftPico \(expected.swiftPicoVersion), PicoKit \(expected.picoKitVersion)); rebuilding firmware from scratch.")
        try fileManager.removeItem(at: buildDirectory)
    }

    private static func writeFirmwareBuildState(_ state: FirmwareBuildState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.pretty.encode(state).write(to: url, options: .atomic)
    }

    private static func installPicoKitDependency(projectRoot: URL, config: PicoKitConfig) throws -> URL {
        let checkout = projectRoot.appendingPathComponent(".build/checkouts/PicoKit", isDirectory: true)

        if !FileManager.default.fileExists(atPath: checkout.appendingPathComponent("Package.swift").path) {
            try clearPicoKitRepoCache(projectRoot: projectRoot)
            print("Resolving PicoKit dependency…")
        }

        do {
            try runProcess(["swift", "package", "resolve"], currentDirectory: projectRoot)
        } catch {
            try clearPicoKitRepoCache(projectRoot: projectRoot)
            try runProcess(["swift", "package", "resolve"], currentDirectory: projectRoot)
        }

        guard FileManager.default.fileExists(atPath: checkout.appendingPathComponent("Package.swift").path) else {
            throw CLIError.message("PicoKit dependency was not resolved at \(checkout.path)")
        }

        let sdk = checkout.appendingPathComponent("Vendor/pico-sdk", isDirectory: true)
        if !FileManager.default.fileExists(atPath: sdk.appendingPathComponent("CMakeLists.txt").path) {
            print("Initializing Pico SDK submodule…")
            try runProcess(["git", "-C", checkout.path, "submodule", "update", "--init", "--recursive"], currentDirectory: projectRoot)
        }
        guard FileManager.default.fileExists(atPath: sdk.appendingPathComponent("CMakeLists.txt").path) else {
            throw CLIError.message("Pico SDK was not initialized inside \(checkout.path)/Vendor/pico-sdk")
        }
        return checkout
    }

    private static func captureProcessOutput(_ command: [String]) throws -> String {
        precondition(!command.isEmpty)
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.message("command failed (exit \(process.terminationStatus)): \(command.joined(separator: " "))")
        }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private static func validateArguments(command: String, arguments: [String]) throws {
        if command == "dependencies" || command == "deps" {
            guard let action = arguments.first, ["resolve", "generate", "remove", "update", "migrate", "show"].contains(action) else {
                throw CLIError.message("usage: swiftpico dependencies resolve|generate|remove|update|migrate|show")
            }
            let consumesName = action == "remove" || action == "update"
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
        let valued: Set<String> = ["--board", "--name", "--template", "--path", "--configuration", "--swift-sdk", "--product", "--uf2", "--volume", "--picotool", "--openocd", "--target", "--device", "--baud", "--context", "--pico-kit-url", "--pico-kit-version", "--pico-kit-path"]
        let flags: Set<String> = ["--force", "--verbose", "--reconnect", "--skip-resolve"]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else { throw CLIError.message("unexpected argument '\(argument)' for \(command)") }
            if valued.contains(argument) {
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else { throw CLIError.message("\(argument) requires a value") }
                index += 2
            } else if flags.contains(argument) {
                index += 1
            } else {
                throw CLIError.message("unknown option '\(argument)' for \(command)")
            }
        }
    }

    private static func validateLibraryArguments(_ arguments: [String]) throws {
        let valued: Set<String> = ["--url", "--from", "--package", "--product", "--target", "--tag", "--name", "--context", "--revision"]
        let flags: Set<String> = ["--skip-resolve"]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if valued.contains(argument) {
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else { throw CLIError.message("\(argument) requires a value") }
                index += 2
            } else if flags.contains(argument) {
                index += 1
            } else {
                throw CLIError.message("unknown option '\(argument)' for add")
            }
        }
    }

    private static func context(_ arguments: [String]) throws -> ProjectContext {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let configURL: URL
        if let path = option("--context", in: arguments) {
            configURL = URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
        } else if let discovered = findContext(from: currentDirectory) {
            configURL = discovered
        } else {
            throw CLIError.message("no swiftpico.json or picokit.json found in this directory or its parents. Run 'swiftpico init --board pico' first, or pass --context /path/to/project.json.")
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw CLIError.message("project context not found: \(configURL.path)")
        }
        let config = try JSONDecoder().decode(PicoKitConfig.self, from: Data(contentsOf: configURL))
        _ = try canonicalBoard(config.board)
        return ProjectContext(root: configURL.deletingLastPathComponent(), config: config)
    }

    private static func findContext(from directory: URL) -> URL? {
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

    private static func findPicoKitRoot(from directory: URL) -> URL? {
        var candidate = directory
        while candidate.path != "/" {
            let package = candidate.appendingPathComponent("Package.swift").path
            let library = candidate.appendingPathComponent("Sources/PicoKitFacade").path
            if FileManager.default.fileExists(atPath: package), FileManager.default.fileExists(atPath: library) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func swiftCompilerPath() -> String? {
        let fileManager = FileManager.default
        var candidates: [String] = []
        if let explicit = ProcessInfo.processInfo.environment["PICO_SWIFTC"], !explicit.isEmpty {
            candidates.append(explicit)
        }
        if let toolchains = ProcessInfo.processInfo.environment["SWIFTLY_TOOLCHAINS_DIR"],
           let installed = try? fileManager.contentsOfDirectory(atPath: toolchains) {
            candidates.append(contentsOf: installed
                .filter { $0.hasPrefix("swift-DEVELOPMENT-SNAPSHOT-") && $0.hasSuffix(".xctoolchain") }
                .sorted(by: >)
                .map {
                    URL(fileURLWithPath: toolchains)
                        .appendingPathComponent($0)
                        .appendingPathComponent("usr/bin/swiftc").path
                })
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent("swiftc").path
            })
        }
        if let toolchains = ProcessInfo.processInfo.environment["SWIFTLY_TOOLCHAINS_DIR"] {
            candidates.append(URL(fileURLWithPath: toolchains)
                .appendingPathComponent("swift-latest.xctoolchain/usr/bin/swiftc").path)
        }
        candidates.append(contentsOf: [
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
            "/usr/bin/swiftc",
        ])
        return candidates.first { fileManager.isExecutableFile(atPath: $0) && !$0.hasSuffix("/.swiftly/bin/swiftc") }
    }

    private static func serialDevices() -> [String] {
        let devices = (try? FileManager.default.contentsOfDirectory(atPath: "/dev"))?.filter {
            $0.hasPrefix("cu.usb") || $0.hasPrefix("ttyACM") || $0.hasPrefix("ttyUSB")
        } ?? []
        return devices.sorted().map { "/dev/\($0)" }
    }

    private static func resetToBootloaderOverUSB() throws {
        let devices = serialDevices()
        guard devices.count == 1, let device = devices.first else {
            let hint = devices.isEmpty
                ? "no USB serial device found"
                : "multiple USB serial devices found (passive reset needs exactly one)"
            throw CLIError.message("cannot request BOOTSEL reset: \(hint)")
        }

        // The Pico SDK treats 1200 baud as a USB CDC request to reboot into
        // BOOTSEL. `stty` opens the device, sends the line-coding request, and
        // closes it, so this works without a serial monitor or extra driver.
        #if os(macOS)
        try runProcess(["stty", "-f", device, "1200", "raw", "-echo"], quiet: true)
        #else
        try runProcess(["stty", "-F", device, "1200", "raw", "-echo"], quiet: true)
        #endif
    }

    private static func waitForBootVolume(timeout: TimeInterval = 8) -> URL? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let volume = findBootVolume() { return volume }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return nil
    }

    private static func ejectBootVolume(_ volume: URL) {
        #if os(macOS)
        try? runProcess(["diskutil", "eject", volume.path], quiet: true)
        #else
        try? runProcess(["umount", volume.path], quiet: true)
        #endif
    }

    private static func isToolAvailable(_ executable: String) -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").contains { directory in
            FileManager.default.isExecutableFile(atPath: "\(directory)/\(executable)")
        }
    }

    private static func findBootVolume() -> URL? {
        // Finder and Disk Arbitration can expose a newly mounted FAT volume
        // before `mountedVolumeURLs` refreshes its metadata. Check the normal
        // macOS mount paths directly first.
        for path in ["/Volumes/RP2350", "/Volumes/RPI-RP2350", "/Volumes/RPI-RP2"] {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: []) ?? []
        return volumes.first(where: isPicoBootVolume)
    }

    private static func findPicotool(_ config: PicoKitConfig, projectRoot: URL) -> String? {
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
                configured.hasPrefix("/") ? configured : projectRoot.appendingPathComponent(configured).standardizedFileURL.path,
                at: 0
            )
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func copyUF2ToVolume(_ source: URL, volume: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: volume.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError.message("Pico boot volume is not mounted at \(volume.path)")
        }
        let destination = volume.appendingPathComponent(source.lastPathComponent)
        let deadline = Date().addingTimeInterval(5)
        var lastError: Error?

        repeat {
            do {
                // The freshly mounted FAT volume can briefly reject writes.
                #if os(macOS)
                try runProcess(["env", "COPYFILE_DISABLE=1", "cp", "-X", source.path, destination.path], quiet: true)
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

    private static func isPicoBootVolume(_ volume: URL) -> Bool {
        let name = (try? volume.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? ""
        return ["RPI-RP2", "RPI-RP2350", "RP2350"].contains(name)
    }

    private static func runProcess(_ command: [String], currentDirectory: URL? = nil, quiet: Bool = false) throws {
        precondition(!command.isEmpty)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = currentDirectory
        if !quiet {
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIError.message("command failed (exit \(process.terminationStatus)): \(command.joined(separator: " "))") }
    }

    fileprivate static let usage = """
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

private struct PicoKitConfig: Codable {
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
        case board, firmwareDirectory, picoSDKPath, picoKitPath, picoKitURL
        case picoKitVersion, picotool, swiftSDK, product, configuration, uf2
        case openOCD, openOCDConfig
        case initializeUSBInterfaceAtStart = "initialize_usb_interface_at_start"
    }
}

private struct FirmwareBuildState: Codable, Equatable {
    let swiftPicoVersion: String
    let picoKitVersion: String
}

private struct ProjectContext {
    let root: URL
    let config: PicoKitConfig

    func url(for path: String) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : root.appendingPathComponent(path).standardizedFileURL
    }
}

private enum CLIError: LocalizedError {
    case usage
    case message(String)
    var errorDescription: String? {
        switch self {
        case .usage: SwiftPicoCommand.usage
        case .message(let text): text
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
