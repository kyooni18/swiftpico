enum PicoChip {
    case rp2040
    case rp2350
}

/// Board configuration used by the host CLI. Generated firmware still imports
/// PicoKit's public board and peripheral APIs.
enum PicoBoard: String {
    case pico
    case picoW = "pico_w"
    case pico2
    case pico2W = "pico2_w"

    var chip: PicoChip {
        self == .pico || self == .picoW ? .rp2040 : .rp2350
    }

    var cmakeName: String { rawValue }

    init?(configurationName: String) {
        switch configurationName.lowercased() {
        case "pico": self = .pico
        case "pico_w", "pico-w": self = .picoW
        case "pico2": self = .pico2
        case "pico2_w", "pico2-w": self = .pico2W
        default: return nil
        }
    }
}
