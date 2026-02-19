import AppKit
import ApplicationServices
import ServiceManagement

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
                    .font: NSFont.systemFont(ofSize: 13, weight: .light),
                    .baselineOffset: 2,
                    .kern: -2
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

