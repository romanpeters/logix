import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

private let systemDefinedKeyCodeOffset = 10_000

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

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case trigger
        case rawButton
    }

    init(id: String, name: String, trigger: ButtonTrigger) {
        self.id = id
        self.name = name
        self.trigger = trigger
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        if let trigger = try container.decodeIfPresent(ButtonTrigger.self, forKey: .trigger) {
            self.trigger = trigger
            return
        }

        if let rawButton = try container.decodeIfPresent(Int.self, forKey: .rawButton) {
            trigger = .mouseButton(rawButton)
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
        if case .mouseButton(let rawButton) = trigger {
            try container.encode(rawButton, forKey: .rawButton)
        }
    }
}

private func normalizedShortcutModifierFlags(from flags: CGEventFlags, keyCode: Int? = nil) -> UInt64 {
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

private func makeSystemDefinedKeyCode(keyType: Int) -> Int {
    systemDefinedKeyCodeOffset + keyType
}

private func systemDefinedKeyType(from keyCode: Int) -> Int? {
    guard keyCode >= systemDefinedKeyCodeOffset else {
        return nil
    }
    return keyCode - systemDefinedKeyCodeOffset
}

private func shortcutLabel(keyCode: Int, modifierFlags: UInt64) -> String {
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

private func keyLabel(for keyCode: Int) -> String {
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

private func systemDefinedKeyLabel(for keyType: Int) -> String {
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

private func isModifierKeyCode(_ keyCode: Int) -> Bool {
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

private func shouldTreatKeyAsShortcutTrigger(keyCode: Int, modifierFlags: UInt64) -> Bool {
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

private func isPrimaryOrSecondaryMouseButton(_ rawButton: Int) -> Bool {
    rawButton == 0 || rawButton == 1
}

private func triggerContainsPrimaryOrSecondaryClick(_ trigger: ButtonTrigger) -> Bool {
    switch trigger {
    case .mouseButton(let rawButton):
        return isPrimaryOrSecondaryMouseButton(rawButton)
    case .syntheticShortcut:
        return false
    case .combo(let first, let second):
        return triggerContainsPrimaryOrSecondaryClick(first) || triggerContainsPrimaryOrSecondaryClick(second)
    }
}

struct ActionSection {
    let title: String
    let actions: [MappedAction]
}

enum MappedAction: String, CaseIterable {
    case passThrough
    case disabled

    case missionControl
    case appExpose
    case showDesktop
    case moveSpaceLeft
    case moveSpaceRight
    case appSwitcherNext
    case appSwitcherPrevious
    case nextWindow
    case previousWindow
    case hideApp
    case minimizeWindow
    case closeWindow
    case lockScreen

    case navigateBack
    case navigateForward
    case reloadPage
    case newTab
    case closeTab
    case reopenClosedTab

    case copy
    case paste
    case cut
    case undo
    case redo
    case selectAll
    case find
    case emojiPicker
    case escape
    case returnKey
    case tabKey
    case pageUp
    case pageDown
    case home
    case end
    case deleteBackward
    case deleteForward

    case playPause
    case nextTrack
    case previousTrack
    case mute
    case volumeUp
    case volumeDown

    case screenshotFullscreen
    case screenshotSelection
    case spotlight
    case siri

    static let menuSections: [ActionSection] = [
        ActionSection(
            title: "Basic",
            actions: [.passThrough, .disabled]
        ),
        ActionSection(
            title: "Desktop & Windows",
            actions: [
                .missionControl, .appExpose, .showDesktop,
                .moveSpaceLeft, .moveSpaceRight,
                .appSwitcherNext, .appSwitcherPrevious,
                .nextWindow, .previousWindow,
                .hideApp, .minimizeWindow, .closeWindow, .lockScreen
            ]
        ),
        ActionSection(
            title: "Navigation & Tabs",
            actions: [.navigateBack, .navigateForward, .reloadPage, .newTab, .closeTab, .reopenClosedTab]
        ),
        ActionSection(
            title: "Editing & Keys",
            actions: [
                .copy, .paste, .cut, .undo, .redo, .selectAll, .find,
                .emojiPicker, .escape, .returnKey, .tabKey,
                .pageUp, .pageDown, .home, .end, .deleteBackward, .deleteForward
            ]
        ),
        ActionSection(
            title: "Media",
            actions: [.playPause, .nextTrack, .previousTrack, .mute, .volumeUp, .volumeDown]
        ),
        ActionSection(
            title: "System",
            actions: [.screenshotFullscreen, .screenshotSelection, .spotlight, .siri]
        )
    ]

    var title: String {
        switch self {
        case .passThrough:
            return "Pass Through (Default)"
        case .disabled:
            return "Disabled"
        case .missionControl:
            return "Mission Control"
        case .appExpose:
            return "Application Windows (App Expose)"
        case .showDesktop:
            return "Show Desktop"
        case .moveSpaceLeft:
            return "Move Space Left"
        case .moveSpaceRight:
            return "Move Space Right"
        case .appSwitcherNext:
            return "Switch App Next"
        case .appSwitcherPrevious:
            return "Switch App Previous"
        case .nextWindow:
            return "Next Window"
        case .previousWindow:
            return "Previous Window"
        case .hideApp:
            return "Hide App"
        case .minimizeWindow:
            return "Minimize Window"
        case .closeWindow:
            return "Close Window"
        case .lockScreen:
            return "Lock Screen"
        case .navigateBack:
            return "Navigate Back"
        case .navigateForward:
            return "Navigate Forward"
        case .reloadPage:
            return "Reload Page"
        case .newTab:
            return "New Tab"
        case .closeTab:
            return "Close Tab"
        case .reopenClosedTab:
            return "Reopen Closed Tab"
        case .copy:
            return "Copy"
        case .paste:
            return "Paste"
        case .cut:
            return "Cut"
        case .undo:
            return "Undo"
        case .redo:
            return "Redo"
        case .selectAll:
            return "Select All"
        case .find:
            return "Find"
        case .emojiPicker:
            return "Emoji Picker"
        case .escape:
            return "Escape"
        case .returnKey:
            return "Return"
        case .tabKey:
            return "Tab"
        case .pageUp:
            return "Page Up"
        case .pageDown:
            return "Page Down"
        case .home:
            return "Home"
        case .end:
            return "End"
        case .deleteBackward:
            return "Delete Backward"
        case .deleteForward:
            return "Delete Forward"
        case .playPause:
            return "Play / Pause"
        case .nextTrack:
            return "Next Track"
        case .previousTrack:
            return "Previous Track"
        case .mute:
            return "Mute"
        case .volumeUp:
            return "Volume Up"
        case .volumeDown:
            return "Volume Down"
        case .screenshotFullscreen:
            return "Screenshot Fullscreen"
        case .screenshotSelection:
            return "Screenshot Selection"
        case .spotlight:
            return "Spotlight Search"
        case .siri:
            return "Siri"
        }
    }

    func perform() {
        switch self {
        case .passThrough, .disabled:
            return
        case .missionControl:
            postConfiguredSymbolicHotKey(
                id: 32,
                fallbackKeyCode: CGKeyCode(kVK_UpArrow),
                fallbackFlags: .maskControl
            )
        case .appExpose:
            postConfiguredSymbolicHotKey(
                id: 33,
                fallbackKeyCode: CGKeyCode(kVK_DownArrow),
                fallbackFlags: .maskControl
            )
        case .showDesktop:
            postKeyPressWithFallback(
                keyCode: CGKeyCode(kVK_F11),
                flags: [],
                preferAppleScript: true
            )
        case .moveSpaceLeft:
            postFirstConfiguredSymbolicHotKey(
                ids: [79, 80],
                fallbackKeyCode: CGKeyCode(kVK_LeftArrow),
                fallbackFlags: .maskControl
            )
        case .moveSpaceRight:
            postFirstConfiguredSymbolicHotKey(
                ids: [81, 82],
                fallbackKeyCode: CGKeyCode(kVK_RightArrow),
                fallbackFlags: .maskControl
            )
        case .appSwitcherNext:
            postKeyPress(keyCode: CGKeyCode(kVK_Tab), flags: .maskCommand)
        case .appSwitcherPrevious:
            postKeyPress(keyCode: CGKeyCode(kVK_Tab), flags: [.maskCommand, .maskShift])
        case .nextWindow:
            postConfiguredSymbolicHotKey(
                id: 27,
                fallbackKeyCode: CGKeyCode(kVK_ANSI_Grave),
                fallbackFlags: .maskCommand
            )
        case .previousWindow:
            postConfiguredSymbolicHotKey(
                id: 27,
                extraFlags: .maskShift,
                fallbackKeyCode: CGKeyCode(kVK_ANSI_Grave),
                fallbackFlags: [.maskCommand, .maskShift]
            )
        case .hideApp:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_H), flags: .maskCommand)
        case .minimizeWindow:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_M), flags: .maskCommand)
        case .closeWindow:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_W), flags: .maskCommand)
        case .lockScreen:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_Q), flags: [.maskCommand, .maskControl])
        case .navigateBack:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_LeftBracket), flags: .maskCommand)
        case .navigateForward:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_RightBracket), flags: .maskCommand)
        case .reloadPage:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_R), flags: .maskCommand)
        case .newTab:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_T), flags: .maskCommand)
        case .closeTab:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_W), flags: .maskCommand)
        case .reopenClosedTab:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_T), flags: [.maskCommand, .maskShift])
        case .copy:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        case .paste:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        case .cut:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_X), flags: .maskCommand)
        case .undo:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_Z), flags: .maskCommand)
        case .redo:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_Z), flags: [.maskCommand, .maskShift])
        case .selectAll:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        case .find:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_F), flags: .maskCommand)
        case .emojiPicker:
            postKeyPress(keyCode: CGKeyCode(kVK_Space), flags: [.maskCommand, .maskControl])
        case .escape:
            postKeyPress(keyCode: CGKeyCode(kVK_Escape), flags: [])
        case .returnKey:
            postKeyPress(keyCode: CGKeyCode(kVK_Return), flags: [])
        case .tabKey:
            postKeyPress(keyCode: CGKeyCode(kVK_Tab), flags: [])
        case .pageUp:
            postKeyPress(keyCode: CGKeyCode(kVK_PageUp), flags: [])
        case .pageDown:
            postKeyPress(keyCode: CGKeyCode(kVK_PageDown), flags: [])
        case .home:
            postKeyPress(keyCode: CGKeyCode(kVK_Home), flags: [])
        case .end:
            postKeyPress(keyCode: CGKeyCode(kVK_End), flags: [])
        case .deleteBackward:
            postKeyPress(keyCode: CGKeyCode(kVK_Delete), flags: [])
        case .deleteForward:
            postKeyPress(keyCode: CGKeyCode(kVK_ForwardDelete), flags: [])
        case .playPause:
            postMediaKey(16)
        case .nextTrack:
            postMediaKey(17)
        case .previousTrack:
            postMediaKey(18)
        case .mute:
            postMediaKey(7)
        case .volumeUp:
            postMediaKey(0)
        case .volumeDown:
            postMediaKey(1)
        case .screenshotFullscreen:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_3), flags: [.maskCommand, .maskShift])
        case .screenshotSelection:
            postKeyPress(keyCode: CGKeyCode(kVK_ANSI_4), flags: [.maskCommand, .maskShift])
        case .spotlight:
            postKeyPress(keyCode: CGKeyCode(kVK_Space), flags: .maskCommand)
        case .siri:
            triggerSiri()
        }
    }

    private func postKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let activeModifiers = postModifierEvents(flags: flags, keyDown: true, source: source)

        guard let downEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let upEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            postModifierKeyUps(activeModifiers, source: source)
            return
        }

        downEvent.flags = flags
        upEvent.flags = flags
        downEvent.post(tap: .cghidEventTap)
        upEvent.post(tap: .cghidEventTap)
        postModifierKeyUps(activeModifiers, source: source)
    }

    private func postKeyPressWithFallback(keyCode: CGKeyCode, flags: CGEventFlags, preferAppleScript: Bool) {
        if preferAppleScript, postKeyPressViaAppleScript(keyCode: keyCode, flags: flags) {
            return
        }
        postKeyPress(keyCode: keyCode, flags: flags)
    }

    private func postConfiguredSymbolicHotKey(
        id: Int,
        extraFlags: CGEventFlags = [],
        fallbackKeyCode: CGKeyCode,
        fallbackFlags: CGEventFlags
    ) {
        guard let configured = symbolicHotKey(id: id) else {
            postKeyPressWithFallback(
                keyCode: fallbackKeyCode,
                flags: fallbackFlags,
                preferAppleScript: true
            )
            return
        }
        postKeyPressWithFallback(
            keyCode: configured.keyCode,
            flags: configured.flags.union(extraFlags),
            preferAppleScript: true
        )
    }

    private func postFirstConfiguredSymbolicHotKey(
        ids: [Int],
        fallbackKeyCode: CGKeyCode,
        fallbackFlags: CGEventFlags
    ) {
        for id in ids {
            if let configured = symbolicHotKey(id: id) {
                postKeyPressWithFallback(
                    keyCode: configured.keyCode,
                    flags: configured.flags,
                    preferAppleScript: true
                )
                return
            }
        }

        postKeyPressWithFallback(
            keyCode: fallbackKeyCode,
            flags: fallbackFlags,
            preferAppleScript: true
        )
    }

    private func postConfiguredSymbolicHotKeyIfAvailable(ids: [Int]) -> Bool {
        for id in ids {
            guard let configured = symbolicHotKey(id: id) else {
                continue
            }
            postKeyPressWithFallback(
                keyCode: configured.keyCode,
                flags: configured.flags,
                preferAppleScript: true
            )
            return true
        }
        return false
    }

    private func symbolicHotKey(id: Int) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        guard let rawSettings = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ),
        let settings = rawSettings as? [String: Any],
        let hotKey = settings[String(id)] as? [String: Any] else {
            return nil
        }

        if let enabled = hotKey["enabled"] as? NSNumber, enabled.intValue == 0 {
            return nil
        }

        guard let value = hotKey["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any],
              parameters.count >= 3,
              let keyCodeNumber = parameters[1] as? NSNumber,
              let modifierNumber = parameters[2] as? NSNumber else {
            return nil
        }

        return (
            keyCode: CGKeyCode(keyCodeNumber.intValue),
            flags: eventFlags(fromSymbolicHotKeyModifiers: modifierNumber.intValue)
        )
    }

    private func eventFlags(fromSymbolicHotKeyModifiers modifiers: Int) -> CGEventFlags {
        var flags: CGEventFlags = []

        if modifiers & (1 << 17) != 0 {
            flags.insert(.maskShift)
        }
        if modifiers & (1 << 18) != 0 {
            flags.insert(.maskControl)
        }
        if modifiers & (1 << 19) != 0 {
            flags.insert(.maskAlternate)
        }
        if modifiers & (1 << 20) != 0 {
            flags.insert(.maskCommand)
        }

        return flags
    }

    private func postModifierEvents(flags: CGEventFlags, keyDown: Bool, source: CGEventSource) -> [CGKeyCode] {
        var activeModifiers: [CGKeyCode] = []
        let mapping: [(CGEventFlags, CGKeyCode)] = [
            (.maskCommand, CGKeyCode(kVK_Command)),
            (.maskShift, CGKeyCode(kVK_Shift)),
            (.maskAlternate, CGKeyCode(kVK_Option)),
            (.maskControl, CGKeyCode(kVK_Control))
        ]

        for (modifierFlag, keyCode) in mapping where flags.contains(modifierFlag) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
                continue
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            activeModifiers.append(keyCode)
        }

        return activeModifiers
    }

    private func postModifierKeyUps(_ activeModifiers: [CGKeyCode], source: CGEventSource) {
        for keyCode in activeModifiers.reversed() {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
                continue
            }
            event.post(tap: .cghidEventTap)
        }
    }

    private func postKeyPressViaAppleScript(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        var modifiers: [String] = []
        if flags.contains(.maskCommand) {
            modifiers.append("command down")
        }
        if flags.contains(.maskShift) {
            modifiers.append("shift down")
        }
        if flags.contains(.maskControl) {
            modifiers.append("control down")
        }
        if flags.contains(.maskAlternate) {
            modifiers.append("option down")
        }

        let usingClause = modifiers.isEmpty ? "" : " using {\(modifiers.joined(separator: ", "))}"
        let script = "tell application \"System Events\" to key code \(Int(keyCode))\(usingClause)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private func postMediaKey(_ keyType: Int32) {
        postMediaKeyEvent(keyType: keyType, isDown: true)
        postMediaKeyEvent(keyType: keyType, isDown: false)
    }

    private func postMediaKeyEvent(keyType: Int32, isDown: Bool) {
        let keyState: Int32 = isDown ? 0xA : 0xB
        let data1 = Int((keyType << 16) | (keyState << 8))

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ),
        let cgEvent = event.cgEvent else {
            return
        }

        cgEvent.post(tap: .cghidEventTap)
    }

    private func triggerSiri() {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.postConfiguredSymbolicHotKeyIfAvailable(ids: [176, 177, 178, 179]) {
                return
            }

            self.postHeldKeyPress(
                keyCode: CGKeyCode(kVK_Function),
                flags: [],
                holdDurationMicros: 450_000
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let workspace = NSWorkspace.shared
                if let siriURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.Siri") {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    workspace.openApplication(at: siriURL, configuration: config) { _, _ in }
                    return
                }

                let siriPath = URL(fileURLWithPath: "/System/Applications/Siri.app")
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                workspace.openApplication(at: siriPath, configuration: config) { _, _ in }
            }
        }
    }

    private func postHeldKeyPress(keyCode: CGKeyCode, flags: CGEventFlags, holdDurationMicros: useconds_t) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let activeModifiers = postModifierEvents(flags: flags, keyDown: true, source: source)
        guard let downEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let upEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            postModifierKeyUps(activeModifiers, source: source)
            return
        }

        downEvent.flags = flags
        upEvent.flags = flags
        downEvent.post(tap: .cghidEventTap)
        usleep(holdDurationMicros)
        upEvent.post(tap: .cghidEventTap)
        postModifierKeyUps(activeModifiers, source: source)
    }
}

final class LearnButtonWindowController: NSWindowController, NSWindowDelegate {
    var onAdd: ((String, ButtonTrigger) -> Void)?
    var onClose: (() -> Void)?
    var hasCapturedTrigger: Bool { resolvedTrigger != nil }

    private let pressedLabel = NSTextField(labelWithString: "Pressed event: none")
    private let nameField = NSTextField()
    private let addButton = NSButton(title: "Add Entry", target: nil, action: nil)
    private var capturedTrigger: ButtonTrigger?
    private var escapeKeyMonitor: Any?

    private var resolvedTrigger: ButtonTrigger? {
        capturedTrigger
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Learn New Button"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        removeEscapeKeyMonitor()
    }

    func updateCapturedMouseButton(rawButton: Int) {
        if isPrimaryOrSecondaryMouseButton(rawButton), isMouseCurrentlyInsideLearnWindow() {
            return
        }
        captureTrigger(.mouseButton(rawButton))
    }

    func updateCapturedSyntheticShortcut(keyCode: Int, modifierFlags: UInt64) {
        guard shouldTreatKeyAsShortcutTrigger(keyCode: keyCode, modifierFlags: modifierFlags) else {
            return
        }
        captureTrigger(.syntheticShortcut(keyCode: keyCode, modifierFlags: modifierFlags))
    }

    func windowWillClose(_ notification: Notification) {
        removeEscapeKeyMonitor()
        onClose?()
    }

    func prepareForPresentation() {
        installEscapeKeyMonitor()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let introLabel = NSTextField(labelWithString: "Press any mouse button or shortcut.")
        introLabel.textColor = .secondaryLabelColor

        let nameLabel = NSTextField(labelWithString: "Name")

        addButton.target = self
        addButton.action = #selector(addEntry)
        addButton.keyEquivalent = "\r"
        addButton.isEnabled = false

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(closeWindow))

        let buttonRow = NSStackView(views: [addButton, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY

        let stack = NSStackView(
            views: [introLabel, pressedLabel, nameLabel, nameField, buttonRow]
        )
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nameChanged),
            name: NSControl.textDidChangeNotification,
            object: nameField
        )

        refreshCapturedLabels()
    }

    @objc private func nameChanged() {
        updateAddButtonState()
    }

    @objc private func addEntry() {
        guard let trigger = resolvedTrigger else {
            return
        }
        let trimmed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? trigger.fallbackName : trimmed
        onAdd?(name, trigger)
        closeWindow()
    }

    @objc private func closeWindow() {
        window?.close()
    }

    private func captureTrigger(_ trigger: ButtonTrigger) {
        guard trigger.isLeaf else {
            return
        }

        capturedTrigger = trigger
        refreshCapturedLabels()
        updateSuggestedNameIfEmpty()
        updateAddButtonState()
    }

    private func refreshCapturedLabels() {
        if let capturedTrigger {
            pressedLabel.stringValue = "Pressed event: \(capturedTrigger.debugLabel)"
        } else {
            pressedLabel.stringValue = "Pressed event: none"
        }
    }

    private func updateSuggestedNameIfEmpty() {
        guard nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if let resolvedTrigger {
            nameField.stringValue = resolvedTrigger.fallbackName
        }
    }

    private func updateAddButtonState() {
        let hasName = !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        addButton.isEnabled = (resolvedTrigger != nil) && hasName
    }

    private func isMouseCurrentlyInsideLearnWindow() -> Bool {
        guard let window else {
            return false
        }
        return NSMouseInRect(NSEvent.mouseLocation, window.frame, false)
    }

    private func installEscapeKeyMonitor() {
        guard escapeKeyMonitor == nil else {
            return
        }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            guard event.keyCode == UInt16(kVK_Escape),
                  let window = self.window,
                  window.isVisible,
                  window.isKeyWindow else {
                return event
            }

            self.closeWindow()
            return nil
        }
    }

    private func removeEscapeKeyMonitor() {
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let mappingsKey = "ButtonMappings"
    private let entriesKey = "ButtonEntries"

    private let menu = NSMenu()
    private var statusItem: NSStatusItem?
    private var buttonEntries: [ButtonEntry] = []
    private var buttonMappings: [String: MappedAction] = [:]
    private var buttonSubmenus: [String: NSMenu] = [:]
    private var buttonGroupItems: [String: NSMenuItem] = [:]
    private var accessibilityStatusItem: NSMenuItem?
    private var startAtLoginItem: NSMenuItem?
    private var learnWindowController: LearnButtonWindowController?
    private var menuIsOpen = false
    private var lastMappedDownTriggerKey: String?
    private var lastMappedDownTimestamp: UInt64 = 0

    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadButtonEntries()
        loadMappings()
        setupStatusItem()
        setupMenu()
        requestAccessibilityPrompt()
        startEventTap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopEventTap()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenuState()
        refreshAccessibilityStatus()
        refreshStartAtLoginState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let title = NSMutableAttributedString(
                string: "L",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                    .baselineOffset: 1
                ]
            )
            title.append(
                NSAttributedString(
                    string: "x",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                        .baselineOffset: -2
                    ]
                )
            )
            button.attributedTitle = title
            button.image = nil
            button.imagePosition = .noImage
            button.toolTip = "MX Master Mapper"
        }
        item.menu = menu
        statusItem = item
    }

    private func setupMenu() {
        buttonSubmenus.removeAll()
        buttonGroupItems.removeAll()
        menu.removeAllItems()
        menu.delegate = self
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "Logix Button Mapper", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        accessibilityStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        accessibilityStatusItem?.isEnabled = false
        if let accessibilityStatusItem {
            menu.addItem(accessibilityStatusItem)
        }

        menu.addItem(.separator())

        for entry in buttonEntries {
            let groupItem = NSMenuItem(title: entry.name, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: entry.name)

            for (sectionIndex, section) in MappedAction.menuSections.enumerated() {
                let sectionItem = NSMenuItem(title: section.title, action: nil, keyEquivalent: "")
                sectionItem.isEnabled = false
                submenu.addItem(sectionItem)

                for action in section.actions {
                    let mapItem = NSMenuItem(title: action.title, action: #selector(setMapping(_:)), keyEquivalent: "")
                    mapItem.target = self
                    mapItem.representedObject = "\(entry.id)|\(action.rawValue)"
                    submenu.addItem(mapItem)
                }

                if sectionIndex < MappedAction.menuSections.count - 1 {
                    submenu.addItem(.separator())
                }
            }

            groupItem.submenu = submenu
            buttonSubmenus[entry.id] = submenu
            buttonGroupItems[entry.id] = groupItem
            menu.addItem(groupItem)
        }

        if buttonEntries.isEmpty {
            let emptyItem = NSMenuItem(title: "No button entries configured", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.addItem(.separator())

        let manageItem = NSMenuItem(title: "Manage Buttons", action: nil, keyEquivalent: "")
        let manageSubmenu = NSMenu(title: "Manage Buttons")

        let learnItem = NSMenuItem(title: "Learn New Button...", action: #selector(openLearnWindow), keyEquivalent: "")
        learnItem.target = self
        manageSubmenu.addItem(learnItem)

        let removeEntryItem = NSMenuItem(title: "Remove Entry", action: nil, keyEquivalent: "")
        let removeSubmenu = NSMenu(title: "Remove Entry")
        for entry in buttonEntries {
            let item = NSMenuItem(title: entry.name, action: #selector(removeEntry(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            removeSubmenu.addItem(item)
        }
        removeEntryItem.isEnabled = !buttonEntries.isEmpty
        removeEntryItem.submenu = removeSubmenu
        manageSubmenu.addItem(removeEntryItem)
        manageItem.submenu = manageSubmenu
        menu.addItem(manageItem)

        menu.addItem(.separator())

        let startAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        startAtLoginItem.target = self
        menu.addItem(startAtLoginItem)
        self.startAtLoginItem = startAtLoginItem

        let openAccessibilityItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        openAccessibilityItem.target = self
        menu.addItem(openAccessibilityItem)

        let restartTapItem = NSMenuItem(title: "Restart Event Tap", action: #selector(restartEventTap), keyEquivalent: "")
        restartTapItem.target = self
        menu.addItem(restartTapItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        refreshMenuState()
        refreshAccessibilityStatus()
        refreshStartAtLoginState()
    }

    @objc private func setMapping(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String else {
            return
        }

        let parts = payload.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              buttonEntries.contains(where: { $0.id == parts[0] }),
              let action = MappedAction(rawValue: parts[1]) else {
            return
        }

        buttonMappings[parts[0]] = action
        saveMappings()
        refreshMenuState()
    }

    @objc private func openLearnWindow() {
        if let learnWindowController {
            presentLearnWindow(learnWindowController)
            return
        }

        let controller = LearnButtonWindowController()
        controller.onAdd = { [weak self] name, trigger in
            self?.addButtonEntry(name: name, trigger: trigger)
        }
        controller.onClose = { [weak self] in
            self?.learnWindowController = nil
        }
        learnWindowController = controller
        presentLearnWindow(controller)
    }

    @objc private func removeEntry(_ sender: NSMenuItem) {
        guard let entryID = sender.representedObject as? String else {
            return
        }

        buttonEntries.removeAll { $0.id == entryID }
        buttonMappings.removeValue(forKey: entryID)

        saveButtonEntries()
        saveMappings()
        setupMenu()
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func restartEventTap() {
        stopEventTap()
        startEventTap()
        refreshAccessibilityStatus()
    }

    @objc private func toggleStartAtLogin() {
        let service = SMAppService.mainApp
        let isEnabled = service.status == .enabled || service.status == .requiresApproval

        do {
            if isEnabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    showInfoAlert(
                        title: "Approval Required",
                        message: "macOS requires approval for this login item. Check System Settings > General > Login Items."
                    )
                }
            }
        } catch {
            showInfoAlert(
                title: "Start at Login",
                message: "Could not update login item: \(error.localizedDescription)"
            )
        }

        refreshStartAtLoginState()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshMenuState() {
        for entry in buttonEntries {
            guard let submenu = buttonSubmenus[entry.id] else {
                continue
            }

            let selectedAction = buttonMappings[entry.id] ?? .passThrough
            for item in submenu.items {
                guard let payload = item.representedObject as? String else {
                    continue
                }
                let parts = payload.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2,
                      let action = MappedAction(rawValue: parts[1]) else {
                    continue
                }
                item.state = (action == selectedAction) ? .on : .off
            }
        }
    }

    private func refreshAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        accessibilityStatusItem?.title = trusted
            ? "Accessibility: Granted"
            : "Accessibility: Not Granted"
    }

    private func refreshStartAtLoginState() {
        guard let startAtLoginItem else {
            return
        }

        let status = SMAppService.mainApp.status
        startAtLoginItem.state = (status == .enabled || status == .requiresApproval) ? .on : .off
    }

    private func flashButtonHighlight(entryID: String) {
        guard menuIsOpen else {
            return
        }
        openSubmenu(for: entryID)
    }

    private func openSubmenu(for entryID: String) {
        guard menuIsOpen,
              let item = buttonGroupItems[entryID],
              let index = menu.items.firstIndex(of: item) else {
            return
        }

        DispatchQueue.main.async {
            self.menu.performActionForItem(at: index)
        }
    }

    private func presentLearnWindow(_ controller: LearnButtonWindowController) {
        controller.prepareForPresentation()
        controller.showWindow(nil)
        if let window = controller.window {
            centerWindowOnActiveScreen(window)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func centerWindowOnActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main

        guard let screen else {
            window.center()
            return
        }

        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.origin.x + (visible.size.width - size.width) / 2.0,
            y: visible.origin.y + (visible.size.height - size.height) / 2.0
        )
        window.setFrameOrigin(origin)
    }

    private func loadButtonEntries() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: entriesKey),
              let decoded = try? JSONDecoder().decode([ButtonEntry].self, from: data) else {
            buttonEntries = []
            return
        }

        let sanitized = sanitizeEntries(decoded)
        if sanitized.isEmpty {
            buttonEntries = []
        } else {
            buttonEntries = sanitized
            if sanitized != decoded {
                saveButtonEntries()
            }
        }
    }

    private func saveButtonEntries() {
        guard let encoded = try? JSONEncoder().encode(buttonEntries) else {
            return
        }
        UserDefaults.standard.set(encoded, forKey: entriesKey)
    }

    private func loadMappings() {
        guard let stored = UserDefaults.standard.dictionary(forKey: mappingsKey) as? [String: String] else {
            buttonMappings = [:]
            return
        }

        let knownIDs = Set(buttonEntries.map(\.id))
        var loaded: [String: MappedAction] = [:]
        var migrated: [String: String] = [:]

        for (storedKey, actionValue) in stored {
            guard let action = MappedAction(rawValue: actionValue) else {
                continue
            }

            if knownIDs.contains(storedKey) {
                loaded[storedKey] = action
                migrated[storedKey] = actionValue
                continue
            }

            if let rawButton = Int(storedKey),
               let entry = buttonEntry(forRawButton: rawButton) {
                loaded[entry.id] = action
                migrated[entry.id] = actionValue
            }
        }

        buttonMappings = loaded
        if migrated != stored {
            UserDefaults.standard.set(migrated, forKey: mappingsKey)
        }
    }

    private func saveMappings() {
        let knownIDs = Set(buttonEntries.map(\.id))
        var payload: [String: String] = [:]
        for (entryID, action) in buttonMappings where knownIDs.contains(entryID) {
            payload[entryID] = action.rawValue
        }
        UserDefaults.standard.set(payload, forKey: mappingsKey)
    }

    private func sanitizeEntries(_ entries: [ButtonEntry]) -> [ButtonEntry] {
        var usedIDs: Set<String> = []
        var usedTriggers: Set<ButtonTrigger> = []
        var sanitized: [ButtonEntry] = []

        for entry in entries {
            guard !entry.id.isEmpty,
                  !entry.name.isEmpty,
                  isValidTrigger(entry.trigger),
                  !usedIDs.contains(entry.id),
                  !usedTriggers.contains(entry.trigger) else {
                continue
            }
            usedIDs.insert(entry.id)
            usedTriggers.insert(entry.trigger)
            sanitized.append(entry)
        }

        return sanitized
    }

    private func isValidTrigger(_ trigger: ButtonTrigger) -> Bool {
        switch trigger {
        case .mouseButton(let rawButton):
            return rawButton >= 0
        case .syntheticShortcut(let keyCode, _):
            return keyCode >= 0 && keyCode <= 50_000
        case .combo:
            // Legacy decode support only; creating/using combo triggers is disabled.
            return false
        }
    }

    private func buttonEntry(forID entryID: String) -> ButtonEntry? {
        buttonEntries.first { $0.id == entryID }
    }

    private func buttonEntry(forRawButton rawButton: Int) -> ButtonEntry? {
        buttonEntries.first {
            if case .mouseButton(let value) = $0.trigger {
                return value == rawButton
            }
            return false
        }
    }

    private func buttonEntry(forTrigger trigger: ButtonTrigger) -> ButtonEntry? {
        buttonEntries.first { $0.trigger == trigger }
    }

    private func addButtonEntry(name: String, trigger: ButtonTrigger) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? trigger.fallbackName : trimmed

        guard isValidTrigger(trigger) else {
            showInfoAlert(title: "Invalid Trigger", message: "The learned trigger format is not supported.")
            return
        }

        if triggerContainsPrimaryOrSecondaryClick(trigger) {
            showInfoAlert(
                title: "Reserved Buttons",
                message: "Left and right click are reserved for safety and cannot be remapped."
            )
            return
        }

        if let existing = buttonEntries.first(where: { $0.trigger == trigger }) {
            showInfoAlert(
                title: "Trigger Already Added",
                message: "\(trigger.debugLabel) is already mapped as \"\(existing.name)\"."
            )
            return
        }

        let entry = ButtonEntry(id: UUID().uuidString, name: finalName, trigger: trigger)
        buttonEntries.append(entry)
        buttonMappings[entry.id] = .passThrough
        saveButtonEntries()
        saveMappings()
        setupMenu()
    }

    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func startEventTap() {
        guard eventTap == nil else {
            return
        }

        let eventMask = mask(for: .leftMouseDown) | mask(for: .leftMouseUp) | mask(for: .leftMouseDragged)
            | mask(for: .rightMouseDown) | mask(for: .rightMouseUp) | mask(for: .rightMouseDragged)
            | mask(for: .otherMouseDown) | mask(for: .otherMouseUp) | mask(for: .otherMouseDragged)
            | mask(for: .keyDown) | mask(for: .keyUp)
            | mask(forRawValue: 14)
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passRetained(event)
            }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            return appDelegate.handleEvent(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        eventTapSource = source
    }

    private func stopEventTap() {
        guard let tap = eventTap else {
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTapSource = nil
        eventTap = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let learningController = learnWindowController?.window?.isVisible == true ? learnWindowController : nil

        if let systemDefined = systemDefinedTrigger(from: event, type: type) {
            if let learningController {
                if systemDefined.isDown {
                    DispatchQueue.main.async {
                        learningController.updateCapturedSyntheticShortcut(
                            keyCode: systemDefined.keyCode,
                            modifierFlags: systemDefined.modifierFlags
                        )
                    }
                }
                return nil
            }

            return routeMappedTriggerEvent(
                trigger: .syntheticShortcut(
                    keyCode: systemDefined.keyCode,
                    modifierFlags: systemDefined.modifierFlags
                ),
                isDown: systemDefined.isDown,
                event: event
            )
        }

        if isMouseEvent(type) {
            let rawButton = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let trigger = ButtonTrigger.mouseButton(rawButton)

            if let learningController {
                if isMouseDownEvent(type) {
                    DispatchQueue.main.async {
                        learningController.updateCapturedMouseButton(rawButton: rawButton)
                    }
                }
                return nil
            }

            return routeMappedTriggerEvent(trigger: trigger, isDown: isMouseDownEvent(type), event: event)
        }

        if type == .keyDown || type == .keyUp {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let modifierFlags = normalizedShortcutModifierFlags(from: event.flags, keyCode: keyCode)
            let shortcutTrigger = ButtonTrigger.syntheticShortcut(keyCode: keyCode, modifierFlags: modifierFlags)
            let isShortcutTrigger = shouldTreatKeyAsShortcutTrigger(
                keyCode: keyCode,
                modifierFlags: modifierFlags
            )

            if let learningController {
                if isShortcutTrigger && type == .keyDown {
                    DispatchQueue.main.async {
                        learningController.updateCapturedSyntheticShortcut(
                            keyCode: keyCode,
                            modifierFlags: modifierFlags
                        )
                    }
                }

                if isShortcutTrigger || !learningController.hasCapturedTrigger {
                    return nil
                }
                return Unmanaged.passRetained(event)
            }

            guard isShortcutTrigger else {
                return Unmanaged.passRetained(event)
            }

            return routeMappedTriggerEvent(trigger: shortcutTrigger, isDown: type == .keyDown, event: event)
        }

        return Unmanaged.passRetained(event)
    }

    private func mask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << type.rawValue
    }

    private func mask(forRawValue rawValue: UInt32) -> CGEventMask {
        CGEventMask(1) << rawValue
    }

    private func isMouseEvent(_ type: CGEventType) -> Bool {
        type == .leftMouseDown
            || type == .leftMouseUp
            || type == .leftMouseDragged
            || type == .rightMouseDown
            || type == .rightMouseUp
            || type == .rightMouseDragged
            || type == .otherMouseDown
            || type == .otherMouseUp
            || type == .otherMouseDragged
    }

    private func isMouseDownEvent(_ type: CGEventType) -> Bool {
        type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
    }

    private func routeMappedTriggerEvent(trigger: ButtonTrigger, isDown: Bool, event: CGEvent) -> Unmanaged<CGEvent>? {
        if triggerContainsPrimaryOrSecondaryClick(trigger) {
            return Unmanaged.passRetained(event)
        }

        guard let entry = buttonEntry(forTrigger: trigger) else {
            return Unmanaged.passRetained(event)
        }

        if isDown {
            DispatchQueue.main.async { [weak self] in
                self?.flashButtonHighlight(entryID: entry.id)
            }
        }

        return runMappedAction(for: entry, isDown: isDown, event: event)
    }

    private func runMappedAction(for entry: ButtonEntry, isDown: Bool, event: CGEvent) -> Unmanaged<CGEvent>? {
        if triggerContainsPrimaryOrSecondaryClick(entry.trigger) {
            return Unmanaged.passRetained(event)
        }

        let action = buttonMappings[entry.id] ?? .passThrough
        switch action {
        case .passThrough:
            return Unmanaged.passRetained(event)
        case .disabled:
            return nil
        default:
            if isDown {
                let triggerKey = entry.trigger.storageKey
                if shouldSuppressDuplicateMappedPress(triggerKey: triggerKey, timestamp: event.timestamp) {
                    return nil
                }
                action.perform()
                recordMappedPress(triggerKey: triggerKey, timestamp: event.timestamp)
            }
            return nil
        }
    }

    private func systemDefinedTrigger(from event: CGEvent, type: CGEventType) -> (keyCode: Int, modifierFlags: UInt64, isDown: Bool)? {
        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return nil
        }

        let data1 = nsEvent.data1
        let keyType = Int((data1 & 0xFFFF0000) >> 16)
        let keyState = Int((data1 & 0x0000FF00) >> 8)

        let isDown: Bool
        switch keyState {
        case 0xA:
            isDown = true
        case 0xB:
            isDown = false
        default:
            return nil
        }

        let keyCode = makeSystemDefinedKeyCode(keyType: keyType)
        let modifierFlags = normalizedShortcutModifierFlags(from: event.flags, keyCode: keyCode)
        return (keyCode, modifierFlags, isDown)
    }

    private func shouldSuppressDuplicateMappedPress(triggerKey: String, timestamp: UInt64) -> Bool {
        guard let lastTriggerKey = lastMappedDownTriggerKey,
              lastTriggerKey != triggerKey,
              timestamp > lastMappedDownTimestamp else {
            return false
        }

        let duplicateWindowNanos: UInt64 = 40_000_000
        return (timestamp - lastMappedDownTimestamp) < duplicateWindowNanos
    }

    private func recordMappedPress(triggerKey: String, timestamp: UInt64) {
        lastMappedDownTriggerKey = triggerKey
        lastMappedDownTimestamp = timestamp
    }
}

private var sharedDelegate: AppDelegate?

@main
enum LogixMouseMapperMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        sharedDelegate = delegate

        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
    }
}
