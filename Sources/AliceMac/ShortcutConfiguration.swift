import AppKit
import Carbon.HIToolbox

enum ShortcutKey: String, CaseIterable, Codable, Identifiable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .a: return UInt16(kVK_ANSI_A)
        case .b: return UInt16(kVK_ANSI_B)
        case .c: return UInt16(kVK_ANSI_C)
        case .d: return UInt16(kVK_ANSI_D)
        case .e: return UInt16(kVK_ANSI_E)
        case .f: return UInt16(kVK_ANSI_F)
        case .g: return UInt16(kVK_ANSI_G)
        case .h: return UInt16(kVK_ANSI_H)
        case .i: return UInt16(kVK_ANSI_I)
        case .j: return UInt16(kVK_ANSI_J)
        case .k: return UInt16(kVK_ANSI_K)
        case .l: return UInt16(kVK_ANSI_L)
        case .m: return UInt16(kVK_ANSI_M)
        case .n: return UInt16(kVK_ANSI_N)
        case .o: return UInt16(kVK_ANSI_O)
        case .p: return UInt16(kVK_ANSI_P)
        case .q: return UInt16(kVK_ANSI_Q)
        case .r: return UInt16(kVK_ANSI_R)
        case .s: return UInt16(kVK_ANSI_S)
        case .t: return UInt16(kVK_ANSI_T)
        case .u: return UInt16(kVK_ANSI_U)
        case .v: return UInt16(kVK_ANSI_V)
        case .w: return UInt16(kVK_ANSI_W)
        case .x: return UInt16(kVK_ANSI_X)
        case .y: return UInt16(kVK_ANSI_Y)
        case .z: return UInt16(kVK_ANSI_Z)
        }
    }

    var label: String {
        rawValue.uppercased()
    }
}

struct ShortcutConfiguration: Equatable, Codable {
    var key: ShortcutKey
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    static let defaultConfig = ShortcutConfiguration(
        key: .a,
        command: true,
        option: false,
        control: false,
        shift: true
    )

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        if shift { flags.insert(.shift) }
        return flags
    }

    var displayString: String {
        var parts: [String] = []
        if command { parts.append("Cmd") }
        if option { parts.append("Option") }
        if control { parts.append("Control") }
        if shift { parts.append("Shift") }
        parts.append(key.label)
        return parts.joined(separator: "+")
    }

    func normalized() -> ShortcutConfiguration {
        if command || option || control || shift {
            return self
        }
        return ShortcutConfiguration(
            key: key,
            command: true,
            option: false,
            control: false,
            shift: false
        )
    }
}

final class ShortcutSettingsStore {
    private let defaults: UserDefaults
    private let storageKey = "alice.globalShortcut.configuration"
    private let ocrDebugFrameEnabledKey = "alice.capture.ocrDebugFrameEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ShortcutConfiguration {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data) else {
            return .defaultConfig
        }
        return decoded.normalized()
    }

    func save(_ configuration: ShortcutConfiguration) {
        let normalized = configuration.normalized()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func loadOCRDebugFrameEnabled() -> Bool {
        guard defaults.object(forKey: ocrDebugFrameEnabledKey) != nil else {
            return true
        }
        return defaults.bool(forKey: ocrDebugFrameEnabledKey)
    }

    func saveOCRDebugFrameEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: ocrDebugFrameEnabledKey)
    }
}
