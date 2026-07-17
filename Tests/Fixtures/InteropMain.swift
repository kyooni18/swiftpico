import MockLCD
import MockTouch
import PicoKit

@_cdecl("app_frame_ready")
public func frameReady(_ byteCount: UInt32) -> Int32 {
  Int32(bitPattern: byteCount)
}

@main
struct InteropFixture {
  static func main() {
    let bytes: [UInt8] = [0x77, 0x89]
    _ = bytes.withUnsafeBufferPointer {
      mock_lcd_checksum($0.baseAddress, UInt32($0.count))
    }
    _ = cpp_adapter_value()
    _ = mock_touch_identifier()
    _ = app_invoke_callback(UInt32(bytes.count))

    let spi = try! PicoSPI(
      .spi0,
      frequency: .megahertz(40),
      sck: .gpio18,
      mosi: .gpio19,
      miso: nil,
      mode: .mode0,
      chipSelect: .gpio17
    )
    try! spi.select()
    try! spi.write(bytes)
    try! spi.deselect()
  }
}
