import AppKit
import LimitNotchCore
import SwiftUI

@main
struct LimitNotchApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        // Accessory: no Dock icon and no menu bar; the panel in the notch is the whole UI.
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
    private let notch = NotchState(geometry: AppDelegate.currentGeometry())
    private var panel: NotchPanel?
    private var pendingShrink: Task<Void, Never>?
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotchPanel(
            contentRect: notch.geometry.panelFrame(expanded: false),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // Above the menu bar and status items, on every Space, including over full-screen apps.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let hostingView = NotchHostingView(rootView: NotchView(store: store, notch: notch))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        hostingView.onHoverChange = { [weak self] hovered in self?.notch.setHovered(hovered) }
        panel.contentView = hostingView
        self.panel = panel

        notch.onExpansionChange = { [weak self] expanded in self?.expansionChanged(expanded) }
        store.start()
        panel.orderFrontRegardless()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screenConfigurationChanged),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(occlusionChanged),
                           name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)

        // A click anywhere else closes a panel that was pinned open with a click.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.notch.dismissPin() }
        }
    }

    private func expansionChanged(_ expanded: Bool) {
        pendingShrink?.cancel()
        if expanded {
            store.refresh()
            setPanelFrame(expanded: true)
        } else {
            // Keep the large window until the collapse spring has played out.
            pendingShrink = Task { [weak self] in
                try? await Task.sleep(for: NotchState.collapseSettle)
                guard !Task.isCancelled, let self, !self.notch.isExpanded else { return }
                self.setPanelFrame(expanded: false)
            }
        }
    }

    private func setPanelFrame(expanded: Bool) {
        panel?.setFrame(notch.geometry.panelFrame(expanded: expanded), display: true)
    }

    @objc private func screenConfigurationChanged(_ notification: Notification) {
        notch.update(geometry: Self.currentGeometry())
        setPanelFrame(expanded: notch.isExpanded)
    }

    @objc private func occlusionChanged(_ notification: Notification) {
        guard let panel else { return }
        notch.isAnimating = panel.occlusionState.contains(.visible)
    }

    @objc private func screensDidSleep(_ notification: Notification) {
        notch.isAnimating = false
    }

    @objc private func screensDidWake(_ notification: Notification) {
        notch.isAnimating = panel?.occlusionState.contains(.visible) ?? true
    }

    /// Prefers the notched built-in display, then any built-in display, then the main screen.
    private static func currentGeometry() -> NotchGeometry {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? screens.first(where: { $0.isBuiltIn })
            ?? NSScreen.main
            ?? screens.first
        else {
            let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
            return NotchGeometry(screenFrame: frame, visibleFrame: frame, safeAreaTop: 0,
                                 auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
        }
        return NotchGeometry(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width
        )
    }
}

private extension NSScreen {
    var isBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }
}

/// Tracks hover with `.activeAlways`, which keeps working while LimitNotch is not the active app.
/// The window always matches the visible notch shape at rest, so its bounds are the hover zone.
private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === hoverArea { onHoverChange?(true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === hoverArea { onHoverChange?(false) }
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
