import Foundation

/// Synchronizes terminal writes while a monitor replaces its device handle
/// after a USB reconnect. Reads use a separate descriptor and cannot block it.
final class SerialWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?

    func open(_ device: String) throws {
        let replacement = try FileHandle(forWritingTo: URL(fileURLWithPath: device))
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
