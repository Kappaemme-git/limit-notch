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
    private var container: NotchContainerView?
    private var pendingShrink: Task<Void, Never>?

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

        let container = NotchContainerView(
            frame: NSRect(origin: .zero, size: notch.geometry.collapsedSize),
            drawingSize: notch.geometry.expandedSize,
            rootView: NotchView(store: store, notch: notch)
        )
        container.onHoverChange = { [weak self] hovered in self?.notch.setHovered(hovered) }
        panel.contentView = container
        self.container = container
        self.panel = panel

        notch.onExpansionChange = { [weak self] expanded in self?.expansionChanged(expanded) }
        store.start()
        panel.orderFrontRegardless()
        if ProcessInfo.processInfo.environment["LIMITNOTCH_DEBUG_EXPANDED"] == "1" {
            notch.setPinned(true)
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screenConfigurationChanged),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    private func expansionChanged(_ expanded: Bool) {
        pendingShrink?.cancel()
        if expanded {
            notch.isAnimating = true
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
        container?.drawingSize = notch.geometry.expandedSize
        setPanelFrame(expanded: notch.isExpanded)
    }

    @objc private func screensDidSleep(_ notification: Notification) {
        notch.isAnimating = false
    }

    @objc private func screensDidWake(_ notification: Notification) {
        notch.isAnimating = true
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
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width,
            scale: screen.backingScaleFactor
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

/// Clips a constant-size SwiftUI surface to the panel's actual window bounds. The mascot and
/// content never relayout as the panel switches between the two window frames.
private final class NotchContainerView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    private let hostingView: FirstClickHostingView
    var drawingSize: CGSize {
        didSet { needsLayout = true }
    }

    init(frame: NSRect, drawingSize: CGSize, rootView: NotchView) {
        self.drawingSize = drawingSize
        hostingView = FirstClickHostingView(rootView: rootView)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        addSubview(hostingView)
        needsLayout = true
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        hostingView.frame = NSRect(x: (bounds.width - drawingSize.width) / 2, y: 0,
                                   width: drawingSize.width, height: drawingSize.height)
    }

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

/// The panel never activates the app, so its window is never key. Accepting the first click lets
/// the service switch respond immediately instead of swallowing a click to focus the window.
private final class FirstClickHostingView: NSHostingView<NotchView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
