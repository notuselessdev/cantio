import Foundation
import AppKit

#if canImport(Sparkle)
import Sparkle
#endif

/// Wraps Sparkle's standard updater so the rest of the app talks to a single
/// neutral surface. When Sparkle isn't linked (e.g. before SPM resolves the
/// package) the controller still compiles — `checkForUpdates()` becomes a
/// no-op so menu wiring stays intact.
@MainActor
final class UpdateController {
    static let shared = UpdateController()

    /// Whether Sparkle is actually wired up at compile time.
    static var isAvailable: Bool {
        #if canImport(Sparkle)
        return true
        #else
        return false
        #endif
    }

    #if canImport(Sparkle)
    private let updater: SPUStandardUpdaterController
    #endif

    private init() {
        #if canImport(Sparkle)
        // `startingUpdater: true` schedules background checks per the
        // `SUFeedURL` / `SUEnableAutomaticChecks` keys in Info.plist.
        // `userDriver: nil` uses Sparkle's default UI (a standard alert).
        self.updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    /// Surfaces Sparkle's "Check for Updates" sheet. Safe to call when no
    /// updater is linked — becomes a no-op.
    func checkForUpdates() {
        #if canImport(Sparkle)
        updater.checkForUpdates(nil)
        #else
        NSLog("Floric: Sparkle not linked; update channel is a stub.")
        #endif
    }
}
