import AppKit
import SwiftUI

@main
struct LimitNotchApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StatusStore()
    private var panel: NotchPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let compact = NSSize(width: NotchLayout.compact, height: NotchLayout.compact)
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: compact),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: IndicatorView(store: store))
        hostingView.frame = NSRect(origin: .zero, size: compact)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        self.panel = panel

        store.onExpansionChange = { [weak self] in self?.positionPanel(animated: true) }
        store.start()
        positionPanel(animated: false)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenConfigurationChanged(_ notification: Notification) {
        positionPanel(animated: false)
    }

    private func positionPanel(animated: Bool) {
        guard let panel else { return }
        let size = store.isExpanded
            ? NSSize(width: NotchLayout.expandedWidth, height: NotchLayout.expandedHeight)
            : NSSize(width: NotchLayout.compact, height: NotchLayout.compact)
        guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopRightArea != nil })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }

        // On a notched display, the indicator sits just to the right of the camera housing.
        let desiredX = screen.auxiliaryTopRightArea.map { $0.minX + 5 }
            ?? screen.frame.midX + 12
        let x = min(max(desiredX, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let y = screen.frame.maxY - size.height - 3
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true, animate: animated)
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
