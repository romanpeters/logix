import AppKit
import ApplicationServices
import Carbon.HIToolbox

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
            return "App Expose"
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

