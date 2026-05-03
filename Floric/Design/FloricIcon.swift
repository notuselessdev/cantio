import SwiftUI

/// Floric mark — squircle with a 5-bar waveform glyph. Reads at menu-bar
/// size; matches the icon described in `preferences.jsx`.
struct FloricIcon: View {
    var size: CGFloat = 64
    var monochrome: Bool = false

    var body: some View {
        let unit = size / 64
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(
                    colors: monochrome
                        ? [Color(white: 0.16), Color(white: 0.04)]
                        : [FL.oklch(0.32, 0.06, 240), FL.oklch(0.16, 0.04, 250)],
                    startPoint: .top, endPoint: .bottom))

            // Inner highlight — diagonal sheen.
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(
                    colors: [.white.opacity(0.10), .clear],
                    startPoint: .top, endPoint: .center))
                .blendMode(.screen)
                .padding(0.5)

            // Waveform — five bars centered, stroked with accent gradient.
            Canvas { ctx, sz in
                let cx = sz.width / 2, cy = sz.height / 2
                let bars: [(CGFloat, CGFloat)] = [(-18, 3), (-9, 9), (0, 15), (9, 7), (18, 2)]
                for (x, h) in bars {
                    var p = Path()
                    p.move(to: CGPoint(x: cx + x * unit, y: cy - h * unit))
                    p.addLine(to: CGPoint(x: cx + x * unit, y: cy + h * unit))
                    if monochrome {
                        ctx.stroke(p, with: .color(.white),
                                   style: StrokeStyle(lineWidth: 3.6 * unit, lineCap: .round))
                    } else {
                        let grad = Gradient(colors: [
                            FL.oklch(0.92, 0.10, 200),
                            FL.oklch(0.78, 0.13, 220)
                        ])
                        ctx.stroke(p,
                            with: .linearGradient(grad,
                                startPoint: CGPoint(x: 0, y: cy),
                                endPoint: CGPoint(x: sz.width, y: cy)),
                            style: StrokeStyle(lineWidth: 3.6 * unit, lineCap: .round))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 14 * unit, y: 4 * unit)
        .shadow(color: .black.opacity(0.18), radius: 2 * unit, y: 1 * unit)
    }
}

/// Stylized waveform glyph (no chrome) — used in menu-bar status area.
struct FloricGlyph: View {
    var size: CGFloat = 14
    var color: Color = .white
    var active: Bool = true

    var body: some View {
        Canvas { ctx, sz in
            let unit = sz.width / 16
            let bars: [(CGFloat, CGFloat)] = [(2, 1), (5, 3), (8, 5), (11, 3), (14, 1)]
            for (x, h) in bars {
                var p = Path()
                let cy = sz.height / 2
                p.move(to: CGPoint(x: x * unit, y: cy - h * unit))
                p.addLine(to: CGPoint(x: x * unit, y: cy + h * unit))
                ctx.stroke(p, with: .color(color.opacity(active ? 1 : 0.7)),
                           style: StrokeStyle(lineWidth: 1.5 * unit, lineCap: .round))
            }
        }
        .frame(width: size * 16/14, height: size)
    }
}
