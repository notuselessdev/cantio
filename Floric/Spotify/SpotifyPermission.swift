import AppKit
import ApplicationServices
import Foundation

/// Tri-state result of querying TCC for AppleEvents automation permission to
/// drive Spotify.
///
/// macOS gates `tell application id "com.spotify.client"` behind the
/// "Automation" privacy section in System Settings. The app must:
/// 1. Declare `NSAppleEventsUsageDescription` in Info.plist (we do).
/// 2. Carry the `com.apple.security.automation.apple-events` entitlement
///    under hardened runtime (we do).
/// 3. Trigger the TCC consent prompt while Spotify is running, then either
///    proceed when granted or surface a recovery path when denied.
enum AutomationPermission: Equatable {
    /// User granted "Automation: Spotify" permission.
    case granted
    /// User denied permission, or it was revoked in System Settings.
    case denied
    /// Not yet decided. Calling `request()` will surface the consent prompt
    /// (Spotify must be running for the prompt to actually appear).
    case notDetermined
    /// Spotify isn't running, so we can't query TCC for it. Treated as
    /// "unknown" — we'll re-check once Spotify is detected as running.
    case targetNotRunning
    /// Any other unexpected OSStatus from `AEDeterminePermissionToAutomateTarget`.
    case unknown
}

/// Wraps the macOS Automation (AppleEvents) permission flow for Spotify.
///
/// Uses `AEDeterminePermissionToAutomateTarget` (macOS 10.14+) which both
/// queries the current state and, when `askUserIfNeeded == true`, surfaces
/// the standard system consent prompt. The prompt only fires while the
/// target app is actually running.
enum SpotifyPermission {
    /// Bundle id of the local Spotify desktop app.
    private static let bundleId = "com.spotify.client"

    /// `errAEEventWouldRequireUserConsent` — TCC has no decision yet.
    /// `CoreServices` does not export this constant in Swift, so we declare it.
    private static let errAEEventWouldRequireUserConsent: OSStatus = -1744

    /// Returns the current permission state without prompting the user.
    static func check() -> AutomationPermission {
        return query(askUser: false)
    }

    /// Surfaces the system consent prompt if the state is undetermined.
    /// Returns the resolved state. No-op if Spotify isn't running.
    static func request() -> AutomationPermission {
        return query(askUser: true)
    }

    /// Opens System Settings → Privacy & Security → Automation so the user
    /// can grant or revoke permission. Falls back to the Privacy root if
    /// the deep link is unavailable.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
        NSWorkspace.shared.open(url)
    }

    private static func query(askUser: Bool) -> AutomationPermission {
        guard let bidData = bundleId.data(using: .utf8) else { return .unknown }

        var addressDesc = AEAddressDesc()
        let createStatus: OSStatus = bidData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OSStatus in
            guard let base = raw.baseAddress else { return OSStatus(-1) }
            return OSStatus(AECreateDesc(typeApplicationBundleID, base, bidData.count, &addressDesc))
        }
        guard createStatus == noErr else { return .unknown }
        defer { AEDisposeDesc(&addressDesc) }

        let status = AEDeterminePermissionToAutomateTarget(
            &addressDesc,
            typeWildCard,
            typeWildCard,
            askUser
        )

        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case errAEEventWouldRequireUserConsent:
            return .notDetermined
        case OSStatus(procNotFound):
            return .targetNotRunning
        default:
            return .unknown
        }
    }
}
