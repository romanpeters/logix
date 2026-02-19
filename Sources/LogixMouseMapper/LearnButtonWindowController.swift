import AppKit
import Carbon.HIToolbox

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

        let introLabel = NSTextField(labelWithString: "Press any mouse button.")
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
