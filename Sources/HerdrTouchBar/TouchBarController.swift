import AppKit
import TouchBarBridge

final class TouchBarController: NSObject, NSTouchBarDelegate {
    private let launcherID = NSTouchBarItem.Identifier("dev.herdr.touchbar.launcher")
    private let contentID = NSTouchBarItem.Identifier("dev.herdr.touchbar.sessions")
    private var launcher: NSCustomTouchBarItem?
    private let bar = NSTouchBar()
    let strip = StripView(frame: NSRect(x: 0, y: 0, width: 960, height: 30))
    var available: Bool { HTBAvailable() }
    private(set) var wantsVisible = true
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        bar.delegate = self
        bar.defaultItemIdentifiers = [contentID]
        bar.principalItemIdentifier = contentID
        let item = NSCustomTouchBarItem(identifier: launcherID)
        let button = NSButton(image: NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Herdr agents")!,
                              target: self, action: #selector(show))
        button.bezelColor = Design.blue
        item.view = button
        if HTBInstallLauncher(item) { launcher = item }
        for notification in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.wantsVisible else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.show() }
            })
        }
    }
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == contentID else { return nil }
        let item = NSCustomTouchBarItem(identifier: contentID)
        item.view = strip
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let width = strip.widthAnchor.constraint(equalToConstant: 960)
        width.priority = .defaultLow; width.isActive = true
        strip.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        return item
    }
    @objc func show() { wantsVisible = true; _ = HTBPresent(bar, launcherID.rawValue) }
    func hide() { wantsVisible = false; HTBDismiss(bar) }
    func shutdown() {
        hide()
        if let launcher { HTBRemoveLauncher(launcher) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }
}
