import AppKit
import SwiftUI
import Combine

/// Custom menu-bar dropdown built on `NSStatusItem` + a borderless `NSPanel`,
/// replacing SwiftUI's `MenuBarExtra(.window)`. The Scene API installs an
/// opaque `MenuBarExtraWindow` whose hosting view chain renders panel content
/// against an in-window backing — which means `.glassEffect()` blurs that
/// in-window backing instead of the desktop, defeating Liquid Glass on
/// macOS 26. Owning our own `NSPanel` (level `.popUpMenu`, `isOpaque = false`,
/// `backgroundColor = .clear`) lets `.glassEffect()` render the way Apple's
/// own Battery / Wi-Fi dropdowns do.
@MainActor
final class StatusBarPopover: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let labelHost: NSHostingView<AnyView>
    private var contentBuilder: (() -> AnyView)?

    init<Label: View>(@ViewBuilder label: @escaping () -> Label) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        labelHost = NSHostingView(rootView: AnyView(label()))
        super.init()
        configureStatusItem()
    }

    func setLabel<Label: View>(@ViewBuilder _ label: () -> Label) {
        labelHost.rootView = AnyView(label())
    }

    func setContent<Content: View>(@ViewBuilder _ content: @escaping () -> Content) {
        contentBuilder = { AnyView(content()) }
        if let panel, let view = panel.contentView as? NSHostingView<AnyView> {
            view.rootView = AnyView(content())
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        // NSStatusItem.variableLength sizes itself to the button's title/image,
        // not to subviews. With a SwiftUI hosting view we have to drive the
        // status item's `length` explicitly each time the hosted view's
        // intrinsic content size changes (track title swap, etc.).
        labelHost.sizingOptions = [.intrinsicContentSize]
        labelHost.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(labelHost)
        NSLayoutConstraint.activate([
            labelHost.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            labelHost.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        // `NSHostingView` posts NSView.frameDidChangeNotification when its
        // intrinsic SwiftUI content resizes (because `sizingOptions` triggers
        // a frame update). KVO on `fittingSize`/`intrinsicContentSize` is not
        // supported on NSHostingView.
        labelHost.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(labelFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification, object: labelHost)
        // Initial sync after this method returns and the hosting view has had
        // a layout pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncStatusItemLength(from: self.labelHost)
        }
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @objc private func labelFrameDidChange(_ note: Notification) {
        syncStatusItemLength(from: labelHost)
    }

    private func syncStatusItemLength(from host: NSHostingView<AnyView>) {
        host.layoutSubtreeIfNeeded()
        let intrinsic = host.intrinsicContentSize
        let fitting = host.fittingSize
        let w = max(intrinsic.width, fitting.width, NSStatusItem.squareLength)
        if abs(statusItem.length - w) > 0.5 {
            statusItem.length = w
        }
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            close()
        } else {
            open()
        }
    }

    private func open() {
        guard let builder = contentBuilder else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        if let host = panel.contentView as? NSHostingView<AnyView> {
            host.rootView = builder()
        }
        positionPanel(panel)
        // Activate so the panel can receive key events (Esc, ⌘,, etc.).
        // `.nonactivatingPanel` keeps Floric from stealing app activation
        // from the frontmost app, matching menubar dropdown semantics.
        NSApp.activate(ignoringOtherApps: false)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()
        statusItem.button?.highlight(true)
    }

    private func close() {
        panel?.orderOut(nil)
        removeEventMonitors()
        statusItem.button?.highlight(false)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 360),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = false
        p.animationBehavior = .utilityWindow
        p.delegate = self

        let content = NSHostingView(rootView: AnyView(EmptyView()))
        content.translatesAutoresizingMaskIntoConstraints = false
        // Size to fit the SwiftUI content's intrinsic dimensions.
        content.sizingOptions = [.intrinsicContentSize]
        p.contentView = content
        return p
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        // Convert the button frame into screen coordinates, then position the
        // panel just below it, right-aligned with the status item (matches
        // system dropdown placement).
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)

        // Let SwiftUI lay out so we can ask for the intrinsic size.
        if let host = panel.contentView as? NSHostingView<AnyView> {
            host.layoutSubtreeIfNeeded()
        }
        let fittingSize = panel.contentView?.fittingSize ?? CGSize(width: 290, height: 360)
        let width = max(fittingSize.width, 290)
        let height = max(fittingSize.height, 80)

        let gap: CGFloat = 6
        var origin = NSPoint(
            x: buttonRectOnScreen.midX - width / 2,
            y: buttonRectOnScreen.minY - height - gap
        )
        // Clamp to visible screen frame so the panel never spills off the right
        // edge when the status item lives near the screen edge.
        let visible = screen.visibleFrame
        if origin.x + width > visible.maxX - 6 { origin.x = visible.maxX - width - 6 }
        if origin.x < visible.minX + 6 { origin.x = visible.minX + 6 }
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)),
                       display: true)
    }

    // MARK: - Outside-click + Esc dismissal

    private func installEventMonitors() {
        removeEventMonitors()
        // Click outside the panel anywhere on screen → dismiss.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        // Esc inside the panel → dismiss. Cmd-Q quit / Cmd-, Settings continue
        // to flow through the responder chain via SwiftUI keyboard shortcuts.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 /* Escape */ {
                self.close()
                return nil
            }
            // Click on the status item itself comes through the local monitor
            // when Floric is key — let `togglePanel` handle it (return event so
            // AppKit dispatches it normally, which closes via the toggle path).
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if event.window === self.statusItem.button?.window {
                    self.close()
                    return nil
                }
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Resign-key fires when the user clicks any other window — treat as
        // dismiss to mirror system dropdown behaviour.
        close()
    }
}
