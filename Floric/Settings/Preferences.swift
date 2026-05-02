import Foundation
import Combine

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

/// User preferences persisted via `UserDefaults`. Observable so SwiftUI views
/// and the floating-window controller react to changes.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let displayMode = "displayMode"
        static let appearanceMode = "appearanceMode"
        static let clickThrough = "clickThrough"
        static let hideWhenPaused = "hideWhenPaused"
        static let windowVisible = "windowVisible"
        static let hotKeyKeyCode = "hotKey.keyCode"
        static let hotKeyModifiers = "hotKey.modifiers"
    }

    @Published var displayMode: LyricsDisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Key.appearanceMode) }
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
        if defaults.object(forKey: Key.hotKeyKeyCode) == nil {
            self.toggleHotKey = .defaultToggle
        } else {
            let keyCode = UInt32(defaults.integer(forKey: Key.hotKeyKeyCode))
            let mods = UInt32(defaults.integer(forKey: Key.hotKeyModifiers))
            self.toggleHotKey = HotKey(keyCode: keyCode, modifiers: mods)
        }
    }
}
