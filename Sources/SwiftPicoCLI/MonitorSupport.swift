import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

private func openSerialWriter(_ path: String) -> Int32 {
    #if os(Linux)
    Glibc.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
    #else
    Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
    #endif
}

private func closeSerialWriter(_ descriptor: Int32) {
    #if os(Linux)
    _ = Glibc.close(descriptor)
    #else
    _ = Darwin.close(descriptor)
    #endif
}

func configureMonitorInput() throws -> termios {
    var settings = termios()
    guard tcgetattr(STDIN_FILENO, &settings) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let saved = settings
    cfmakeraw(&settings)
    // Preserve Ctrl-C as a monitor exit instead of forwarding it to firmware.
    settings.c_lflag |= tcflag_t(ISIG)
    guard tcsetattr(STDIN_FILENO, TCSANOW, &settings) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return saved
}

func restoreMonitorInput(_ settings: termios) {
    var settings = settings
    _ = tcsetattr(STDIN_FILENO, TCSANOW, &settings)
}

func configureSerialPort(_ path: String, baud: speed_t) throws {
    let descriptor = openSerialWriter(path)
    guard descriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { closeSerialWriter(descriptor) }

    var settings = termios()
    guard tcgetattr(descriptor, &settings) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    cfmakeraw(&settings)
    guard cfsetspeed(&settings, baud) == 0,
          tcsetattr(descriptor, TCSANOW, &settings) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

func readMonitorInput() -> Data? {
    var buffer = [UInt8](repeating: 0, count: 256)
    let count = buffer.withUnsafeMutableBytes { bytes in
        #if os(Linux)
        Glibc.read(STDIN_FILENO, bytes.baseAddress, bytes.count)
        #else
        Darwin.read(STDIN_FILENO, bytes.baseAddress, bytes.count)
        #endif
    }
    guard count > 0 else { return nil }
    return Data(buffer.prefix(Int(count)))
}

/// Synchronizes terminal writes while a monitor replaces its device handle
/// after a USB reconnect. Reads use a separate descriptor and cannot block it.
final class SerialWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?

    func open(_ device: String) throws {
        // An ordinary open of a macOS USB modem may wait indefinitely for
        // carrier detection. Open nonblocking to acquire the descriptor, then
        // restore ordinary blocking writes for the terminal session.
        let descriptor = openSerialWriter(device)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            closeSerialWriter(descriptor)
            throw error
        }
        let replacement = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        lock.lock()
        let previous = handle
        handle = replacement
        lock.unlock()
        try? previous?.close()
    }

    func close() {
        lock.lock()
        let previous = handle
        handle = nil
        lock.unlock()
        try? previous?.close()
    }

    func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.write(contentsOf: data)
    }
}
