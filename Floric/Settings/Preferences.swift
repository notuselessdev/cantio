import Foundation
import Combine
import ServiceManagement

/// Display mode for the floating lyrics window.
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

/// Visual appearance for the floating lyrics window.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case glass
    case solidDark
    case solidLight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glass: return "Glass"
        case .solidDark: return "Solid Dark"
        case .solidLight: return "Solid Light"
        }
    }
}

/// Font size scale for the floating lyrics window. Four discrete steps so a
/// slider can snap between values.
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

    /// Active (currently-playing) line size in points.
    var activeSize: CGFloat {
        switch self {
        case .small: return 18
        case .medium: return 22
        case .large: return 26
        case .xlarge: return 30
        }
    }

    /// Inactive / body line size in points.
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

/// User preferences persisted via `UserDefaults`. Observable so SwiftUI views
/// and the floating-window controller react to changes.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let displayMode = "displayMode"
        static let appearanceMode = "appearanceMode"
        static let fontSize = "fontSize"
        static let clickThrough = "clickThrough"
        static let hideWhenPaused = "hideWhenPaused"
        static let windowVisible = "windowVisible"
        static let launchAtLogin = "launchAtLogin"
        static let hotKeyKeyCode = "hotKey.keyCode"
        static let hotKeyModifiers = "hotKey.modifiers"
    }

    @Published var displayMode: LyricsDisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Key.appearanceMode) }
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

    @Published var windowVisible: Bool {
        didSet { defaults.set(windowVisible, forKey: Key.windowVisible) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLaunchAtLogin()
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
        let raw = defaults.string(forKey: Key.displayMode) ?? LyricsDisplayMode.singleLine.rawValue
        self.displayMode = LyricsDisplayMode(rawValue: raw) ?? .singleLine
        let appearanceRaw = defaults.string(forKey: Key.appearanceMode) ?? AppearanceMode.glass.rawValue
        self.appearanceMode = AppearanceMode(rawValue: appearanceRaw) ?? .glass
        if defaults.object(forKey: Key.fontSize) == nil {
            self.fontSize = .medium
        } else {
            self.fontSize = FontSize(rawValue: defaults.integer(forKey: Key.fontSize)) ?? .medium
        }
        self.clickThrough = defaults.bool(forKey: Key.clickThrough)
        // Default true unless explicitly stored false.
        if defaults.object(forKey: Key.hideWhenPaused) == nil {
            self.hideWhenPaused = true
        } else {
            self.hideWhenPaused = defaults.bool(forKey: Key.hideWhenPaused)
        }
        if defaults.object(forKey: Key.windowVisible) == nil {
            self.windowVisible = true
        } else {
            self.windowVisible = defaults.bool(forKey: Key.windowVisible)
        }
        // Login-item state is mirrored from the actual `SMAppService` status
        // when known, so a manual toggle in System Settings stays in sync.
        let storedLaunch = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        self.launchAtLogin = Self.currentLoginItemEnabled(fallback: storedLaunch)
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
