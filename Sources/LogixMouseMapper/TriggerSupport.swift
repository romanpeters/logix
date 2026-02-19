import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

let systemDefinedKeyCodeOffset = 10_000

indirect enum ButtonTrigger: Codable, Hashable {
    case mouseButton(Int)
    case syntheticShortcut(keyCode: Int, modifierFlags: UInt64)
    case combo(first: ButtonTrigger, second: ButtonTrigger)

    private enum CodingKeys: String, CodingKey {
        case type
        case rawButton
        case keyCode
        case modifierFlags
        case first
        case second
    }

    private enum TriggerType: String, Codable {
        case mouse
        case shortcut
        case combo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TriggerType.self, forKey: .type)
        switch type {
        case .mouse:
            let rawButton = try container.decode(Int.self, forKey: .rawButton)
            self = .mouseButton(rawButton)
        case .shortcut:
            let keyCode = try container.decode(Int.self, forKey: .keyCode)
            let modifierFlags = try container.decode(UInt64.self, forKey: .modifierFlags)
            self = .syntheticShortcut(keyCode: keyCode, modifierFlags: modifierFlags)
        case .combo:
            let first = try container.decode(ButtonTrigger.self, forKey: .first)
            let second = try container.decode(ButtonTrigger.self, forKey: .second)
            self = .combo(first: first, second: second)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mouseButton(let rawButton):
            try container.encode(TriggerType.mouse, forKey: .type)
            try container.encode(rawButton, forKey: .rawButton)
        case .syntheticShortcut(let keyCode, let modifierFlags):
            try container.encode(TriggerType.shortcut, forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifierFlags, forKey: .modifierFlags)
        case .combo(let first, let second):
            try container.encode(TriggerType.combo, forKey: .type)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        }
    }

    var storageKey: String {
        switch self {
        case .mouseButton(let rawButton):
            return "mouse:\(rawButton)"
        case .syntheticShortcut(let keyCode, let modifierFlags):
            return "shortcut:\(modifierFlags):\(keyCode)"
        case .combo(let first, let second):
            return "combo:\(first.storageKey)+\(second.storageKey)"
        }
    }

    var debugLabel: String {
        switch self {
        case .mouseButton(let rawButton):
            return "Mouse button \(rawButton)"
        case .syntheticShortcut(let keyCode, let modifierFlags):
            return "Shortcut \(shortcutLabel(keyCode: keyCode, modifierFlags: modifierFlags))"
        case .combo(let first, let second):
            return "\(first.debugLabel) then \(second.debugLabel)"
        }
    }

    var isLeaf: Bool {
        switch self {
        case .mouseButton, .syntheticShortcut:
            return true
        case .combo:
            return false
        }
    }

    var comboParts: (first: ButtonTrigger, second: ButtonTrigger)? {
        guard case .combo(let first, let second) = self else {
            return nil
        }
        return (first, second)
    }

    var fallbackName: String {
        switch self {
        case .mouseButton(let rawButton):
            return "Button \(rawButton)"
        case .syntheticShortcut(let keyCode, let modifierFlags):
            return "Button \(shortcutLabel(keyCode: keyCode, modifierFlags: modifierFlags))"
        case .combo(let first, let second):
            return "\(first.fallbackName) + \(second.fallbackName)"
        }
    }
}

struct ButtonEntry: Codable, Hashable {
    let id: String
    var name: String
    var trigger: ButtonTrigger
    var requiresDoublePress: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case trigger
        case rawButton
        case requiresDoublePress
    }

    init(id: String, name: String, trigger: ButtonTrigger, requiresDoublePress: Bool = false) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.requiresDoublePress = requiresDoublePress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        if let trigger = try container.decodeIfPresent(ButtonTrigger.self, forKey: .trigger) {
            self.trigger = trigger
            requiresDoublePress = try container.decodeIfPresent(Bool.self, forKey: .requiresDoublePress) ?? false
            return
        }

        if let rawButton = try container.decodeIfPresent(Int.self, forKey: .rawButton) {
            trigger = .mouseButton(rawButton)
            requiresDoublePress = try container.decodeIfPresent(Bool.self, forKey: .requiresDoublePress) ?? false
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .trigger,
            in: container,
            debugDescription: "Missing trigger information."
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(requiresDoublePress, forKey: .requiresDoublePress)
        if case .mouseButton(let rawButton) = trigger {
            try container.encode(rawButton, forKey: .rawButton)
        }
    }
}

func normalizedShortcutModifierFlags(from flags: CGEventFlags, keyCode: Int? = nil) -> UInt64 {
    var normalized: CGEventFlags = []
    if flags.contains(.maskControl) {
        normalized.insert(.maskControl)
    }
    if flags.contains(.maskAlternate) {
        normalized.insert(.maskAlternate)
    }
    if flags.contains(.maskShift) {
        normalized.insert(.maskShift)
    }
    if flags.contains(.maskCommand) {
        normalized.insert(.maskCommand)
    }
    if flags.contains(.maskSecondaryFn) {
        normalized.insert(.maskSecondaryFn)
    }

    if keyCode == Int(kVK_Function) {
        normalized.remove(.maskSecondaryFn)
    }

    return normalized.rawValue
}

func makeSystemDefinedKeyCode(keyType: Int) -> Int {
    systemDefinedKeyCodeOffset + keyType
}

func systemDefinedKeyType(from keyCode: Int) -> Int? {
    guard keyCode >= systemDefinedKeyCodeOffset else {
        return nil
    }
    return keyCode - systemDefinedKeyCodeOffset
}

func shortcutLabel(keyCode: Int, modifierFlags: UInt64) -> String {
    let flags = CGEventFlags(rawValue: modifierFlags)
    var parts: [String] = []

    if flags.contains(.maskControl) {
        parts.append("Ctrl")
    }
    if flags.contains(.maskAlternate) {
        parts.append("Option")
    }
    if flags.contains(.maskShift) {
        parts.append("Shift")
    }
    if flags.contains(.maskCommand) {
        parts.append("Cmd")
    }
    if flags.contains(.maskSecondaryFn) {
        parts.append("Fn")
    }

    parts.append(keyLabel(for: keyCode))
    return parts.joined(separator: "+")
}

func keyLabel(for keyCode: Int) -> String {
    if let systemKeyType = systemDefinedKeyType(from: keyCode) {
        return systemDefinedKeyLabel(for: systemKeyType)
    }

    switch keyCode {
    case Int(kVK_Tab):
        return "Tab"
    case Int(kVK_Space):
        return "Space"
    case Int(kVK_Return):
        return "Return"
    case Int(kVK_Escape):
        return "Esc"
    case Int(kVK_LeftArrow):
        return "Left"
    case Int(kVK_RightArrow):
        return "Right"
    case Int(kVK_UpArrow):
        return "Up"
    case Int(kVK_DownArrow):
        return "Down"
    case Int(kVK_Function):
        return "Fn"
    case Int(kVK_F1):
        return "F1"
    case Int(kVK_F2):
        return "F2"
    case Int(kVK_F3):
        return "F3"
    case Int(kVK_F4):
        return "F4"
    case Int(kVK_F5):
        return "F5"
    case Int(kVK_F6):
        return "F6"
    case Int(kVK_F7):
        return "F7"
    case Int(kVK_F8):
        return "F8"
    case Int(kVK_F9):
        return "F9"
    case Int(kVK_F10):
        return "F10"
    case Int(kVK_F11):
        return "F11"
    case Int(kVK_F12):
        return "F12"
    case Int(kVK_F13):
        return "F13"
    case Int(kVK_F14):
        return "F14"
    case Int(kVK_F15):
        return "F15"
    case Int(kVK_F16):
        return "F16"
    case Int(kVK_F17):
        return "F17"
    case Int(kVK_F18):
        return "F18"
    case Int(kVK_F19):
        return "F19"
    case Int(kVK_F20):
        return "F20"
    default:
        return "Key \(keyCode)"
    }
}

func systemDefinedKeyLabel(for keyType: Int) -> String {
    switch keyType {
    case 0:
        return "Volume Up"
    case 1:
        return "Volume Down"
    case 2:
        return "Brightness Up"
    case 3:
        return "Brightness Down"
    case 7:
        return "Mute"
    case 10:
        return "Mirror Display"
    case 16:
        return "Play/Pause"
    case 17:
        return "Next Track"
    case 18:
        return "Previous Track"
    case 19:
        return "Fast Forward"
    case 20:
        return "Rewind"
    default:
        return "System Key \(keyType)"
    }
}

func isModifierKeyCode(_ keyCode: Int) -> Bool {
    switch keyCode {
    case Int(kVK_Shift), Int(kVK_RightShift),
         Int(kVK_Control), Int(kVK_RightControl),
         Int(kVK_Option), Int(kVK_RightOption),
         Int(kVK_Command), Int(kVK_RightCommand):
        return true
    default:
        return false
    }
}

func shouldTreatKeyAsShortcutTrigger(keyCode: Int, modifierFlags: UInt64) -> Bool {
    guard !isModifierKeyCode(keyCode) else {
        return false
    }

    if systemDefinedKeyType(from: keyCode) != nil {
        return true
    }

    if keyCode == Int(kVK_Function) {
        return true
    }

    switch keyCode {
    case Int(kVK_F1), Int(kVK_F2), Int(kVK_F3), Int(kVK_F4), Int(kVK_F5),
         Int(kVK_F6), Int(kVK_F7), Int(kVK_F8), Int(kVK_F9), Int(kVK_F10),
         Int(kVK_F11), Int(kVK_F12), Int(kVK_F13), Int(kVK_F14), Int(kVK_F15),
         Int(kVK_F16), Int(kVK_F17), Int(kVK_F18), Int(kVK_F19), Int(kVK_F20):
        return true
    default:
        break
    }

    let flags = CGEventFlags(rawValue: modifierFlags)
    return flags.contains(.maskCommand)
        || flags.contains(.maskControl)
        || flags.contains(.maskAlternate)
        || flags.contains(.maskSecondaryFn)
}

func isPrimaryOrSecondaryMouseButton(_ rawButton: Int) -> Bool {
    rawButton == 0 || rawButton == 1
}

func triggerContainsPrimaryOrSecondaryClick(_ trigger: ButtonTrigger) -> Bool {
    switch trigger {
    case .mouseButton(let rawButton):
        return isPrimaryOrSecondaryMouseButton(rawButton)
    case .syntheticShortcut:
        return false
    case .combo(let first, let second):
        return triggerContainsPrimaryOrSecondaryClick(first) || triggerContainsPrimaryOrSecondaryClick(second)
    }
}
