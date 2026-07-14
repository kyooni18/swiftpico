import PicoKit
import MockCMake

@main
struct DependencyModes {
    static func main() {
        _ = mock_cmake_value()
        _ = source_only_value()
        _ = header_adapter_value()
        _ = cpp_adapter_identifier()
    }
}
