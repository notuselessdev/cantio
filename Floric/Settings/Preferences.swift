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

/// User preferences persisted via `UserDefaults`. Observable so SwiftUI views
/// and the floating-window controller react to changes.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let displayMode = "displayMode"
        static let clickThrough = "clickThrough"
        static let hideWhenPaused = "hideWhenPaused"
        static let windowVisible = "windowVisible"
    }

    @Published var displayMode: LyricsDisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Key.displayMode) ?? LyricsDisplayMode.singleLine.rawValue
        self.displayMode = LyricsDisplayMode(rawValue: raw) ?? .singleLine
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
    }
}
