import SwiftUI

/// First-run setup assistant. A welcome flourish (rising chime + icon reveal)
/// followed by four personalization steps that bind straight to `Preferences`
/// — every choice applies live, so the user can already see it land in the
/// preview. Closing at any point keeps whatever's selected.
struct OnboardingView: View {
    @ObservedObject var prefs: Preferences
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var step = 0

    private var tone: FL.Tone { colorScheme == .dark ? .dark : .light }
    private var palette: FL.Palette { FL.palette(tone: tone, hue: prefs.accentHue) }

    /// Match the other surfaces (`LyricsContentView`, `MenuBarPanel`): when
    /// Reduce Transparency or Increase Contrast is on, drop the glass material
    /// for an opaque fill so lyrics-window-style legibility holds here too.
    private var degradeToSolid: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    /// Text color for the filled accent button. The accent's lightness flips
    /// across tones (light tone ≈ 0.62, dark tone ≈ 0.78), so white only holds
    /// contrast on the darker light-tone accent — use near-black on the bright
    /// dark-tone accent. Documented exception to the no-inline-color rule.
    private var onAccent: Color {
        tone == .dark ? FL.oklch(0.16, 0.008, 250) : .white
    }

    private static let lastStep = 3

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.86)
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity))
    }

    var body: some View {
        ZStack {
            if degradeToSolid {
                palette.bg.ignoresSafeArea()
            } else {
                VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
                    .ignoresSafeArea()
                // Subtle tone wash over the material. Mirrors SettingsView's
                // base fill — documented exception to no-inline-color.
                (tone == .dark ? FL.oklch(0.16, 0.008, 250) : FL.oklch(0.98, 0.003, 250))
                    .opacity(0.4)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Group {
                    switch step {
                    case 0: accentPage
                    case 1: linesPage
                    case 2: fontPage
                    default: launchPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .transition(pageTransition)
                .id(step)

                footer
            }
            .padding(.vertical, 36)
        }
        .frame(width: 580, height: 600)
        // Esc dismisses the assistant from the keyboard (keeps live selections).
        .onExitCommand(perform: onFinish)
    }

    // MARK: - Navigation

    private func advance() {
        if step >= Self.lastStep {
            onFinish()
        } else {
            withAnimation(motion) { step += 1 }
        }
    }

    private func back() {
        guard step > 0 else { return }
        withAnimation(motion) { step -= 1 }
    }

    // MARK: - Pages

    private var accentPage: some View {
        stepScaffold(
            title: "Pick an accent",
            subtitle: "Tints the active lyric line and controls."
        ) {
            VStack(spacing: 24) {
                OBAccentPicker(hue: $prefs.accentHue, palette: palette)
                lyricPreview
            }
        }
    }

    private var linesPage: some View {
        stepScaffold(
            title: "How many lines?",
            subtitle: "Show just the current line, or a rolling stack."
        ) {
            VStack(spacing: 24) {
                OBSegmented(
                    options: ["1", "3", "5"],
                    selection: Binding(
                        get: {
                            let v = prefs.linesVisible
                            if v <= 1 { return "1" }
                            if v <= 3 { return "3" }
                            return "5"
                        },
                        set: { prefs.linesVisible = Int($0) ?? 3 }),
                    palette: palette)
                .accessibilityLabel("Lines visible")
                lyricPreview
            }
        }
    }

    private var fontPage: some View {
        stepScaffold(
            title: "Set the size",
            subtitle: "How large the floating lyrics read."
        ) {
            VStack(spacing: 24) {
                OBSegmented(
                    options: FontSize.allCases.map(\.shortLabel),
                    selection: Binding(
                        get: { prefs.fontSize.shortLabel },
                        set: { newLabel in
                            if let s = FontSize.allCases.first(where: { $0.shortLabel == newLabel }) {
                                prefs.fontSize = s
                            }
                        }),
                    palette: palette)
                .accessibilityLabel("Lyric font size")
                lyricPreview
            }
        }
    }

    private var launchPage: some View {
        stepScaffold(
            title: "Open at login?",
            subtitle: "Start Cantio automatically so lyrics are always ready."
        ) {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    Image(systemName: "power")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.text)
                        Text("You can change this later in Settings.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textMuted)
                    }
                    Spacer()
                    FlToggle(value: $prefs.launchAtLogin, palette: palette)
                        .accessibilityLabel("Launch at login")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.bgElev)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 0.5)))
            }
        }
    }

    // MARK: - Shared pieces

    private func stepScaffold<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.text)
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    /// Live sample that mirrors the real floating pill: the current line sits
    /// in a glass capsule tinted by the accent, the neighbors fall back blurred
    /// and dimmed by distance — exactly how the overlay renders a rolling
    /// stack. Reflects accent, font size, and line count as the user picks them.
    private var lyricPreview: some View {
        let lines = [
            "Just a small town girl",
            "Living in a lonely world",
            "She took the midnight train going anywhere",
            "Just a city boy",
            "Born and raised in South Detroit",
        ]
        let count = max(1, min(prefs.linesVisible, lines.count))
        let activeIndex = count / 2
        return VStack(spacing: 14) {
            ForEach(0..<count, id: \.self) { i in
                let dist = abs(i - activeIndex)
                if dist == 0 {
                    Text(lines[i])
                        .font(.system(size: prefs.fontSize.activeSize, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(activePillBackground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Neighbors recede: lighter weight, dimmer, blurrier the
                    // further from the active line — the depth cue the real
                    // overlay uses so the eye lands on the current lyric.
                    Text(lines[i])
                        .font(.system(size: prefs.fontSize.bodySize, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .blur(radius: Double(dist) * 1.6 + 0.4)
                        .opacity(max(0.25, 1 - Double(dist) * 0.22))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 150)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .background(previewBackdrop)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of lyrics with the current accent, size, and line count")
    }

    /// Glass capsule behind the active line. Degrades to a solid accent-tinted
    /// fill under Reduce Transparency / Increase Contrast, mirroring the pill.
    @ViewBuilder private var activePillBackground: some View {
        if degradeToSolid {
            Capsule().fill(palette.accentSoft)
                .overlay(Capsule().strokeBorder(palette.accent.opacity(0.5), lineWidth: 1))
        } else {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        }
    }

    /// A dark desktop-like backdrop so the glass pill reads the way it does over
    /// a wallpaper — always dark regardless of the assistant's tone. Documented
    /// exception to no-inline-color (it simulates the desktop, not chrome).
    private var previewBackdrop: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(
                colors: [FL.oklch(0.20, 0.02, prefs.accentHue), FL.oklch(0.12, 0.03, prefs.accentHue)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var footer: some View {
        ZStack {
            // Dots centered to the window, independent of the side buttons'
            // differing widths (welcome step has no Back button).
            OBPageDots(count: Self.lastStep + 1, current: step, palette: palette)

            HStack {
                // Leading slot: Back once past the welcome, otherwise a
                // low-emphasis Skip (Esc also dismisses — see `.onExitCommand`).
                if step > 0 {
                    Button(action: back) {
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textMuted)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .frame(minWidth: 44, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                } else {
                    Button(action: onFinish) {
                        Text("Skip")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textMuted)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .frame(minWidth: 44, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip setup")
                }

                Spacer()

                Button(action: advance) {
                    Text(step == Self.lastStep ? "Done" : "Continue")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(onAccent)
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .frame(minHeight: 40)
                        .background(Capsule().fill(palette.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 24)
    }
}

// MARK: - Onboarding controls

/// Larger accent swatches than the Settings row — 30pt circles clear the 28pt
/// hit-target floor for a first-touch screen.
private struct OBAccentPicker: View {
    @Binding var hue: Double
    let palette: FL.Palette

    // (hue angle, human name for VoiceOver). Swatch fill is a raw OKLCH hue —
    // it *is* the choice — documented exception to no-inline-color.
    private let swatches: [(hue: Double, name: String)] = [
        (220, "Blue"), (160, "Teal"), (120, "Green"), (90, "Lime"),
        (50, "Amber"), (340, "Pink"), (280, "Purple"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(swatches, id: \.hue) { s in
                let active = abs(s.hue - hue) < 1
                Button {
                    hue = s.hue
                } label: {
                    Circle()
                        .fill(FL.oklch(0.72, 0.13, s.hue))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle().strokeBorder(active ? palette.text : .clear, lineWidth: 2)
                                .padding(-4))
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(active ? 1 : 0))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.name)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accent color")
    }
}

/// Segmented control sized up for onboarding (36pt tall) with the same look as
/// the Settings `SegmentedPicker`.
private struct OBSegmented: View {
    let options: [String]
    @Binding var selection: String
    let palette: FL.Palette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                let active = o.lowercased() == selection.lowercased()
                Button {
                    selection = o
                } label: {
                    Text(o)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(active ? palette.text : palette.textMuted)
                        .frame(minWidth: 40)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(active ? palette.bgElev : .clear)
                                .shadow(color: .black.opacity(active ? 0.12 : 0), radius: 1, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(o)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.border))
    }
}

private struct OBPageDots: View {
    let count: Int
    let current: Int
    let palette: FL.Palette

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                let active = i == current
                // Active dot reads by shape (wider capsule) as well as color,
                // so progress isn't conveyed by hue alone.
                Capsule()
                    .fill(active ? palette.accent : palette.textFaint.opacity(0.4))
                    .frame(width: active ? 16 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
