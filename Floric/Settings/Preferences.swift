import Foundation
import Combine
import ServiceManagement

/// Display mode for the floating lyrics window. Retained for backward
/// compatibility; new UI prefers `linesVisible` (1 = single, >1 = stack).
enum LyricsDisplayMode: String, CaseIterable, Identifiable {
    case singleLine
    case multiLine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .singleLine: return "Single line"
        case .multiLine: return "Multi-line"
        }
    }
}

/// Window silhouette — controls layout / chrome.
enum WindowStyle: String, CaseIterable, Identifiable {
    case pill
    case minimal
    case fullscreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pill: return "Pill"
        case .minimal: return "Minimal"
        case .fullscreen: return "Fullscreen"
        }
    }
}

/// Background fill for windowed styles (currently `minimal`). Pill and
/// fullscreen render their own backdrop and ignore this.
enum BackgroundStyle: String, CaseIterable, Identifiable {
    case glass
    case solid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glass: return "Glass"
        case .solid: return "Solid"
        }
    }
}

/// Color theme override.
enum Tone: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum FontSize: Int, CaseIterable, Identifiable, Comparable {
    case small = 0
    case medium = 1
    case large = 2
    case xlarge = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .xlarge: return "Extra Large"
        }
    }

    var activeSize: CGFloat {
        switch self {
        case .small: return 18
        case .medium: return 22
        case .large: return 26
        case .xlarge: return 30
        }
    }

    var bodySize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 14
        case .large: return 16
        case .xlarge: return 18
        }
    }

    static func < (lhs: FontSize, rhs: FontSize) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let displayMode = "displayMode"
        static let windowStyle = "windowStyle"
        static let backgroundStyle = "backgroundStyle"
        static let glassOpacity = "glassOpacity"
        static let legacyWindowPreset = "windowPreset"
        static let tone = "tone"
        static let accentHue = "accentHue"
        static let fontSize = "fontSize"
        static let clickThrough = "clickThrough"
        static let hideWhenPaused = "hideWhenPaused"
        static let alwaysOnTop = "alwaysOnTop"
        static let windowVisible = "windowVisible"
        static let launchAtLogin = "launchAtLogin"
        static let linesVisible = "linesVisible"
        static let hotKeyKeyCode = "hotKey.keyCode"
        static let hotKeyModifiers = "hotKey.modifiers"
    }

    @Published var displayMode: LyricsDisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }

    @Published var windowStyle: WindowStyle {
        didSet {
            defaults.set(windowStyle.rawValue, forKey: Key.windowStyle)
            displayMode = (linesVisible <= 1) ? .singleLine : .multiLine
        }
    }

    @Published var backgroundStyle: BackgroundStyle {
        didSet { defaults.set(backgroundStyle.rawValue, forKey: Key.backgroundStyle) }
    }

    /// Tint opacity over the visual-effect blur when `backgroundStyle == .glass`.
    /// 0 = pure blur (most transparent), 1 = fully tinted (least transparent).
    @Published var glassOpacity: Double {
        didSet { defaults.set(glassOpacity, forKey: Key.glassOpacity) }
    }

    @Published var tone: Tone {
        didSet { defaults.set(tone.rawValue, forKey: Key.tone) }
    }

    @Published var accentHue: Double {
        didSet { defaults.set(accentHue, forKey: Key.accentHue) }
    }

    @Published var fontSize: FontSize {
        didSet { defaults.set(fontSize.rawValue, forKey: Key.fontSize) }
    }

    @Published var clickThrough: Bool {
        didSet { defaults.set(clickThrough, forKey: Key.clickThrough) }
    }

    @Published var hideWhenPaused: Bool {
        didSet { defaults.set(hideWhenPaused, forKey: Key.hideWhenPaused) }
    }

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }

    @Published var windowVisible: Bool {
        didSet { defaults.set(windowVisible, forKey: Key.windowVisible) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    @Published var linesVisible: Int {
        didSet {
            defaults.set(linesVisible, forKey: Key.linesVisible)
            displayMode = (linesVisible <= 1) ? .singleLine : .multiLine
        }
    }

    @Published var toggleHotKey: HotKey {
        didSet {
            defaults.set(Int(toggleHotKey.keyCode), forKey: Key.hotKeyKeyCode)
            defaults.set(Int(toggleHotKey.modifiers), forKey: Key.hotKeyModifiers)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let legacyPresetRaw = defaults.string(forKey: Key.legacyWindowPreset)
        let styleRaw = defaults.string(forKey: Key.windowStyle)
        let bgRaw = defaults.string(forKey: Key.backgroundStyle)
        let toneRaw = defaults.string(forKey: Key.tone)

        if let styleRaw, let s = WindowStyle(rawValue: styleRaw) {
            self.windowStyle = s
        } else {
            switch legacyPresetRaw {
            case "minimal": self.windowStyle = .minimal
            case "fullscreen": self.windowStyle = .fullscreen
            case "glass", "solid": self.windowStyle = .minimal
            default: self.windowStyle = .pill
            }
        }
        if let bgRaw, let b = BackgroundStyle(rawValue: bgRaw) {
            self.backgroundStyle = b
        } else {
            self.backgroundStyle = (legacyPresetRaw == "solid") ? .solid : .glass
        }
        self.tone = toneRaw.flatMap(Tone.init(rawValue:)) ?? .auto
        self.glassOpacity = defaults.object(forKey: Key.glassOpacity) as? Double ?? 0.4

        self.accentHue = defaults.object(forKey: Key.accentHue) as? Double ?? 220

        let raw = defaults.string(forKey: Key.displayMode) ?? LyricsDisplayMode.singleLine.rawValue
        self.displayMode = LyricsDisplayMode(rawValue: raw) ?? .singleLine
        if defaults.object(forKey: Key.fontSize) == nil {
            self.fontSize = .medium
        } else {
            self.fontSize = FontSize(rawValue: defaults.integer(forKey: Key.fontSize)) ?? .medium
        }
        self.clickThrough = defaults.bool(forKey: Key.clickThrough)
        if defaults.object(forKey: Key.hideWhenPaused) == nil {
            self.hideWhenPaused = true
        } else {
            self.hideWhenPaused = defaults.bool(forKey: Key.hideWhenPaused)
        }
        if defaults.object(forKey: Key.alwaysOnTop) == nil {
            self.alwaysOnTop = true
        } else {
            self.alwaysOnTop = defaults.bool(forKey: Key.alwaysOnTop)
        }
        if defaults.object(forKey: Key.windowVisible) == nil {
            self.windowVisible = true
        } else {
            self.windowVisible = defaults.bool(forKey: Key.windowVisible)
        }
        let storedLaunch = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        self.launchAtLogin = Self.currentLoginItemEnabled(fallback: storedLaunch)
        self.linesVisible = defaults.object(forKey: Key.linesVisible) as? Int ?? 3
        if defaults.object(forKey: Key.hotKeyKeyCode) == nil {
            self.toggleHotKey = .defaultToggle
        } else {
            let keyCode = UInt32(defaults.integer(forKey: Key.hotKeyKeyCode))
            let mods = UInt32(defaults.integer(forKey: Key.hotKeyModifiers))
            self.toggleHotKey = HotKey(keyCode: keyCode, modifiers: mods)
        }
    }

    // MARK: - Launch at login

    private static func currentLoginItemEnabled(fallback: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return true
            case .notRegistered, .notFound, .requiresApproval: return false
            @unknown default: return fallback
            }
        }
        return fallback
    }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            NSLog("Floric: failed to update login item: \(error.localizedDescription)")
        }
    }
}
