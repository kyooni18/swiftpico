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

private func configureSerialDescriptor(_ descriptor: Int32, baud: speed_t) throws {
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

final class SerialTrafficStats: @unchecked Sendable {
    private let lock = NSLock()
    private var sentBytes = 0
    private var receivedBytes = 0

    func recordSent(_ count: Int) {
        lock.lock()
        sentBytes += count
        lock.unlock()
    }

    func recordReceived(_ count: Int) {
        lock.lock()
        receivedBytes += count
        lock.unlock()
    }

    var sent: Int {
        lock.lock()
        defer { lock.unlock() }
        return sentBytes
    }

    var received: Int {
        lock.lock()
        defer { lock.unlock() }
        return receivedBytes
    }
}

/// Owns one full-duplex serial descriptor. A macOS modem device is a byte
/// stream, so opening separate read and write handles can split or consume
/// traffic unpredictably across resets.
final class SerialConnection: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32 = -1

    func open(_ device: String, baud: speed_t) throws {
        // An ordinary open of a macOS USB modem may wait indefinitely for
        // carrier detection. Open nonblocking to acquire the descriptor, then
        // restore blocking I/O after configuring the same full-duplex handle.
        let replacement = openSerialWriter(device)
        guard replacement >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        do {
            try configureSerialDescriptor(replacement, baud: baud)
        } catch {
            closeSerialWriter(replacement)
            throw error
        }
        let flags = fcntl(replacement, F_GETFL)
        guard flags >= 0, fcntl(replacement, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            closeSerialWriter(replacement)
            throw error
        }
        lock.lock()
        let previous = descriptor
        descriptor = replacement
        lock.unlock()
        if previous >= 0 { closeSerialWriter(previous) }
    }

    func close() {
        lock.lock()
        let previous = descriptor
        descriptor = -1
        lock.unlock()
        if previous >= 0 { closeSerialWriter(previous) }
    }

    func read() -> Data? {
        lock.lock()
        let current = descriptor
        lock.unlock()
        guard current >= 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                #if os(Linux)
                Glibc.read(current, bytes.baseAddress, bytes.count)
                #else
                Darwin.read(current, bytes.baseAddress, bytes.count)
                #endif
            }
            if count > 0 { return Data(buffer.prefix(Int(count))) }
            if count == 0 { return nil }
            if errno != EINTR { return nil }
        }
    }

    @discardableResult
    func write(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor >= 0 else { return false }
        var succeeded = true
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count: Int
                #if os(Linux)
                count = Glibc.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                #else
                count = Darwin.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                #endif
                if count > 0 {
                    offset += count
                } else if count < 0 && errno == EINTR {
                    continue
                } else {
                    succeeded = false
                    return
                }
            }
        }
        return succeeded
    }
}
