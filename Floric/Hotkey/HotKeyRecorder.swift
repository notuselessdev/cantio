import AppKit
import SwiftUI
import Carbon.HIToolbox

/// SwiftUI view for capturing a global hotkey. Click to start recording, then
/// press a key combination including at least one modifier.
struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey
    @State private var isRecording = false

    var body: some View {
        HotKeyRecorderRepresentable(hotKey: $hotKey, isRecording: $isRecording)
            .frame(height: 24)
    }
}

private struct HotKeyRecorderRepresentable: NSViewRepresentable {
    @Binding var hotKey: HotKey
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = { newKey in
            hotKey = newKey
            isRecording = false
        }
        view.onToggleRecording = { recording in
            isRecording = recording
        }
        view.refreshTitle(hotKey: hotKey, recording: isRecording)
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.refreshTitle(hotKey: hotKey, recording: isRecording)
    }
}

final class RecorderView: NSView {
    private let button = NSButton(title: "", target: nil, action: nil)
    private var monitor: Any?
    private var recording = false

    var onCapture: ((HotKey) -> Void)?
    var onToggleRecording: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(toggleRecording)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func refreshTitle(hotKey: HotKey, recording: Bool) {
        if recording {
            button.title = "Press shortcut…"
        } else {
            button.title = hotKey.displayString
        }
    }

    @objc private func toggleRecording() {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        recording = true
        onToggleRecording?(true)
        button.title = "Press shortcut…"
        if monitor != nil { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event: event)
        }
    }

    private func stopRecording() {
        recording = false
        onToggleRecording?(false)
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(event: NSEvent) -> NSEvent? {
        if event.type == .keyDown {
            // Escape cancels.
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbon = HotKey.carbonModifiers(from: mods)
            // Require at least one modifier other than shift.
            let strong = UInt32(cmdKey | optionKey | controlKey)
            guard carbon & strong != 0 else { return nil }
            let key = HotKey(keyCode: event.keyCode, eventModifiers: mods)
            onCapture?(key)
            stopRecording()
            return nil
        }
        return event
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
