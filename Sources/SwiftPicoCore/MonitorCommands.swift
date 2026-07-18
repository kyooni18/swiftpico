import Dispatch
import Foundation

#if os(macOS)
  import Darwin
#else
  import Glibc
#endif

extension SwiftPicoCommand {
  private static func writeMonitorStatus(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }

  static func monitor(_ arguments: [String]) throws {
    do {
      try monitorImpl(arguments)
    } catch let failure as StageFailure {
      throw failure
    } catch {
      let subject = option("--device", in: arguments) ?? "the detected USB serial device"
      throw StageFailure(
        stage: "monitor",
        subject: subject,
        recovery: "run 'swiftpico devices'; reconnect the board, or pass --device <serial-device>",
        underlying: error
      )
    }
  }

  private static func monitorImpl(_ arguments: [String]) throws {
    let detectedDevices = serialDevices()
    let explicitDevice = option("--device", in: arguments)
    var device = try SerialMonitorConfiguration.selectDevice(
      explicit: explicitDevice, detected: detectedDevices)
    if explicitDevice == nil { print("Using serial device \(device)") }
    let baud = option("--baud", in: arguments) ?? "115200"
    let baudValue = try SerialMonitorConfiguration.baud(from: baud)
    let restoreTerminal: (() -> Void)?
    if isatty(STDIN_FILENO) != 0 {
      let savedTerminal = try configureMonitorInput()
      restoreTerminal = { restoreMonitorInput(savedTerminal) }
    } else {
      restoreTerminal = nil
    }
    defer { restoreTerminal?() }
    let traffic = SerialTrafficStats()

    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    interrupt.setEventHandler {
      restoreTerminal?()
      writeMonitorStatus(
        "Serial monitor stopped. Sent \(traffic.sent) bytes; received \(traffic.received) bytes.")
      Foundation.exit(0)
    }
    interrupt.resume()

    let connection = SerialConnection()
    try connection.open(device, baud: speed_t(baudValue))
    defer { connection.close() }
    let inputThread = Thread {
      while true {
        guard let data = readMonitorInput() else { return }
        var offset = 0
        while offset < data.count {
          let acceptedBeforeAttempt = offset
          let completed = connection.write(data, offset: &offset)
          traffic.recordSent(offset - acceptedBeforeAttempt)
          if completed { break }
          connection.close()
          guard arguments.contains("--reconnect") else { return }
          // Preserve bytes typed during a CDC reset. The main monitor loop
          // owns reconnection; retrying this same buffer lets the input side
          // resume automatically once the replacement descriptor is ready.
          Thread.sleep(forTimeInterval: 0.25)
        }
      }
    }
    inputThread.qualityOfService = .userInteractive
    inputThread.start()

    FileHandle.standardOutput.write(
      Data(
        "Monitoring \(device) at \(baud) baud. Type to send; press Ctrl-C to stop.\n".utf8
      ))
    while true {
      guard let data = connection.read() else {
        connection.close()
        guard arguments.contains("--reconnect") else {
          writeMonitorStatus(
            "Serial monitor stopped. Sent \(traffic.sent) bytes; received \(traffic.received) bytes."
          )
          return
        }
        print("Serial device disconnected; waiting to reconnect…")
        while true {
          let candidate: String
          if let explicitDevice {
            guard FileManager.default.fileExists(atPath: explicitDevice) else {
              Thread.sleep(forTimeInterval: 0.25)
              continue
            }
            candidate = explicitDevice
          } else {
            guard
              let detected = SerialMonitorConfiguration.reconnectCandidate(
                explicit: nil, detected: serialDevices()
              )
            else {
              Thread.sleep(forTimeInterval: 0.25)
              continue
            }
            candidate = detected
          }
          do {
            try connection.open(candidate, baud: speed_t(baudValue))
            device = candidate
            break
          } catch {
            // The device node can be published before its CDC
            // endpoints are ready. Retry the full-duplex handle.
            connection.close()
          }
          Thread.sleep(forTimeInterval: 0.25)
        }
        print("Serial device reconnected at \(device).")
        continue
      }
      traffic.recordReceived(data.count)
      FileHandle.standardOutput.write(data)
    }
  }

}
