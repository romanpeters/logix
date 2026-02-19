import AppKit

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
