import SwiftUI

/// Full-screen first-run flourish: the app mark scales up from the center over
/// a slowly drifting, accent-tinted backdrop while the rising chime plays, then
/// auto-advances into the setup steps. Tap, Return, or Esc skip ahead early.
///
/// Honors Reduce Motion: no scale-up, no drifting blobs (a static gradient),
/// no chime — and a shorter dwell before advancing.
struct OnboardingSplashView: View {
    let accentHue: Double
    let playChime: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var revealed = false
    @State private var didStart = false

    var body: some View {
        ZStack {
            background
            VStack(spacing: 24) {
                CantioIcon(size: 132)
                    .scaleEffect(reduceMotion ? 1 : (revealed ? 1 : 0.2))
                    .opacity(revealed ? 1 : 0)
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("Cantio")
                        .font(.system(size: 52, weight: .bold))
                        .tracking(-1.2)
                    Text("Karaoke-grade Spotify lyrics, floating over your desktop.")
                        .font(.system(size: 18, weight: .medium))
                        .opacity(0.82)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed || reduceMotion ? 0 : 18)
            }
            .padding(40)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
        .onExitCommand(perform: onContinue)
        .onAppear(perform: start)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome to Cantio. Karaoke-grade Spotify lyrics, floating over your desktop.")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Continue to setup")
    }

    private func start() {
        guard !didStart else { return }
        didStart = true
        if !reduceMotion { playChime() }
        withAnimation(reduceMotion ? .easeOut(duration: 0.35) : .spring(response: 0.72, dampingFraction: 0.74)) {
            revealed = true
        }
        // Auto-advance into the steps once the moment has landed.
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 2.2 : 4.8)) {
            onContinue()
        }
    }

    // MARK: - Background

    /// A translucent, blurred panel over the desktop (`.hudWindow` vibrancy
    /// darkens what's behind so white text reads), washed with slowly drifting
    /// accent-tinted blobs. Degrades to a solid gradient under Reduce
    /// Transparency / Increase Contrast, mirroring the app's other surfaces.
    @ViewBuilder private var background: some View {
        if reduceTransparency {
            LinearGradient(
                colors: [FL.oklch(0.22, 0.05, accentHue), FL.oklch(0.10, 0.03, accentHue + 30)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            ZStack {
                VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
                if reduceMotion {
                    LinearGradient(
                        colors: [FL.oklch(0.6, 0.16, accentHue).opacity(0.35),
                                 FL.oklch(0.6, 0.16, accentHue + 40).opacity(0.22)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    TimelineView(.animation) { ctx in
                        DriftingBlobs(
                            time: ctx.date.timeIntervalSinceReferenceDate,
                            accentHue: accentHue)
                    }
                }
            }
        }
    }
}

/// Three large, heavily-blurred accent-family blobs drifting on sine paths.
/// Translucent — they tint the blurred desktop showing through rather than
/// painting an opaque base. Colors are raw OKLCH (decorative backdrop,
/// documented exception to no-inline-color).
private struct DriftingBlobs: View {
    let time: Double
    let accentHue: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                blob(hueOffset: 0, speed: 0.50, phase: 0, w: w, h: h)
                blob(hueOffset: 45, speed: 0.42, phase: 2.1, w: w, h: h)
                blob(hueOffset: -55, speed: 0.62, phase: 4.2, w: w, h: h)
            }
        }
    }

    private func blob(hueOffset: Double, speed: Double, phase: Double,
                      w: CGFloat, h: CGFloat) -> some View {
        // Wide, fast-enough drift to read as continuous motion, plus a slow
        // scale breathing so the wash never looks static.
        let x = 0.5 + 0.42 * sin(time * speed + phase)
        let y = 0.5 + 0.38 * cos(time * speed * 0.85 + phase * 1.3)
        let pulse = 1 + 0.14 * sin(time * speed * 1.6 + phase)
        let r = min(w, h) * 0.85 * pulse
        return Circle()
            .fill(FL.oklch(0.62, 0.16, accentHue + hueOffset))
            .frame(width: r, height: r)
            .blur(radius: 140)
            .opacity(0.45)
            .position(x: w * x, y: h * y)
    }
}
