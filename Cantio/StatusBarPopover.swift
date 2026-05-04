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
    private static let maxTitleWidth: CGFloat = 240
    private static let marqueeStepInterval: TimeInterval = 1.0 / 30.0
    private static let marqueePointsPerSecond: CGFloat = 18
    private static let statusTitlePadding: CGFloat = 14

    private let statusItem: NSStatusItem
    private let monitor: SpotifyMonitor
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var contentBuilder: (() -> AnyView)?
    private var cancellables = Set<AnyCancellable>()
    private var marqueeTimer: Timer?
    private var fullStatusTitle = ""
    private var marqueeOffset: CGFloat = 0
    private var marqueeDirection: CGFloat = 1

    init(monitor: SpotifyMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "com.mayronalves.cantio.statusItem"
        super.init()
        configureStatusItem()
        observeMonitor()
    }

    func setContent<Content: View>(@ViewBuilder _ content: @escaping () -> Content) {
        contentBuilder = { AnyView(content()) }
        if let panel, let view = panel.contentView as? NSHostingView<AnyView> {
            view.rootView = AnyView(content())
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.imagePosition = .noImage
        button.toolTip = "Cantio"
        button.identifier = NSUserInterfaceItemIdentifier("com.mayronalves.cantio.statusButton")
        button.setAccessibilityLabel("Cantio")
        button.cell?.wraps = false
        button.cell?.lineBreakMode = .byClipping
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        updateStatusItemLabel()
    }

    private func observeMonitor() {
        monitor.$nowPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemLabel() }
            .store(in: &cancellables)
    }

    private func updateStatusItemLabel() {
        guard let button = statusItem.button else { return }
        if let displayText {
            button.toolTip = "Cantio: \(displayText)"
            button.setAccessibilityLabel("Cantio: \(displayText)")
        } else {
            button.toolTip = "Cantio"
            button.setAccessibilityLabel("Cantio")
        }
        let nextTitle = displayText.map { "♪ \($0)" } ?? "♪"
        if nextTitle != fullStatusTitle {
            fullStatusTitle = nextTitle
            marqueeOffset = 0
            marqueeDirection = 1
            updateStatusButtonFrame()
            updateMarqueeTimer()
        }
        statusItem.isVisible = true
    }

    private func updateStatusButtonFrame() {
        guard let button = statusItem.button else { return }
        if fullStatusTitle == "♪" {
            button.image = nil
            button.attributedTitle = statusAttributedTitle(fullStatusTitle)
            statusItem.length = NSStatusItem.squareLength
        } else {
            button.attributedTitle = NSAttributedString()
            button.image = renderStatusTitle(offset: marqueeOffset)
            button.imagePosition = .imageOnly
            statusItem.length = min(fullStatusTitleWidth, Self.maxTitleWidth)
        }
    }

    private func updateMarqueeTimer() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil

        guard fullStatusTitleWidth > Self.maxTitleWidth,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return }

        let timer = Timer(timeInterval: Self.marqueeStepInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceMarquee() }
        }
        RunLoop.main.add(timer, forMode: .common)
        marqueeTimer = timer
    }

    private var fullStatusTitleWidth: CGFloat {
        ceil(statusAttributedTitle(fullStatusTitle).size().width) + Self.statusTitlePadding
    }

    private func advanceMarquee() {
        guard fullStatusTitle.count > 1 else { return }
        let maxOffset = max(0, fullStatusTitleWidth - Self.maxTitleWidth)
        marqueeOffset += marqueeDirection * Self.marqueePointsPerSecond * Self.marqueeStepInterval
        if marqueeOffset >= maxOffset {
            marqueeOffset = maxOffset
            marqueeDirection = -1
        } else if marqueeOffset <= 0 {
            marqueeOffset = 0
            marqueeDirection = 1
        }
        updateStatusButtonFrame()
    }

    private func statusAttributedTitle(_ title: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        paragraph.alignment = .left
        let menuBarFont = NSFont.menuBarFont(ofSize: 0)
        let font = NSFont.systemFont(ofSize: menuBarFont.pointSize, weight: .semibold)
        return NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private func renderStatusTitle(offset: CGFloat) -> NSImage {
        let imageWidth = min(fullStatusTitleWidth, Self.maxTitleWidth)
        let imageHeight = NSStatusBar.system.thickness
        let imageSize = NSSize(width: imageWidth, height: imageHeight)
        let scale = statusItem.button?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let pixelsWide = max(1, Int(ceil(imageWidth * scale)))
        let pixelsHigh = max(1, Int(ceil(imageHeight * scale)))
        let image = NSImage(size: imageSize)
        let maskTitle = NSMutableAttributedString(attributedString: statusAttributedTitle(fullStatusTitle))
        maskTitle.addAttribute(.foregroundColor, value: NSColor.black,
                               range: NSRange(location: 0, length: maskTitle.length))
        let attributedTitle = maskTitle
        let textSize = attributedTitle.size()
        let y = (imageHeight - textSize.height) / 2

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaFirst],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            image.isTemplate = true
            return image
        }

        rep.size = imageSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        NSGraphicsContext.current?.shouldAntialias = true
        attributedTitle.draw(at: CGPoint(x: Self.statusTitlePadding / 2 - offset, y: y))
        NSGraphicsContext.restoreGraphicsState()

        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private var displayText: String? {
        guard let np = monitor.nowPlaying, np.state == .playing, !np.title.isEmpty else { return nil }
        let artist = np.artist.trimmingCharacters(in: .whitespaces)
        return artist.isEmpty ? np.title : "\(np.title) · \(artist)"
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
        // `.nonactivatingPanel` keeps Cantio from stealing app activation
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
        // Default left-align: panel's left edge under the status item's left
        // edge. If the panel would spill off the right edge, flip to
        // right-aligned (panel's right edge under the status item's right
        // edge) — same fallback the system menus use.
        let visible = screen.visibleFrame
        let edgeMargin: CGFloat = 6
        var originX = buttonRectOnScreen.minX
        if originX + width > visible.maxX - edgeMargin {
            originX = buttonRectOnScreen.maxX - width
        }
        originX = min(max(originX, visible.minX + edgeMargin), visible.maxX - width - edgeMargin)
        var origin = NSPoint(x: originX, y: buttonRectOnScreen.minY - height - gap)
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
            // when Cantio is key — let `togglePanel` handle it (return event so
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
