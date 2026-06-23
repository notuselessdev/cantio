import AppKit
import SwiftUI

/// Derives a few dominant hues from album artwork so the karaoke backdrop and
/// procedural art tints track the playing song's cover instead of a hash of
/// its id. The artwork image is already fetched over the network for display
/// (the fullscreen header thumbnail), so extraction reuses the same Spotify
/// CDN image — it adds no new host egress beyond what the UI already loads.
@MainActor
final class ArtworkColors: ObservableObject {
    /// Dominant hues (degrees, 0–360) for the current track, or nil when no
    /// artwork is available / the cover is near-grayscale. Consumers fall back
    /// to the deterministic hash hues in that case.
    @Published private(set) var hues: [Double]?

    private var loadedTrackId: String?
    private var task: Task<Void, Never>?

    /// Fetch + extract for the given track. No-op when the track is unchanged,
    /// so it's safe to call on every `nowPlaying` update.
    func update(trackId: String?, artworkURL: String?) {
        guard trackId != loadedTrackId else { return }
        loadedTrackId = trackId
        task?.cancel()
        hues = nil
        guard let trackId, let s = artworkURL, let url = URL(string: s) else { return }
        task = Task { [weak self] in
            let extracted = await Self.fetchAndExtract(url: url)
            guard !Task.isCancelled else { return }
            // Drop a late result for a track we've already skipped past.
            guard let self, self.loadedTrackId == trackId else { return }
            self.hues = extracted
        }
    }

    private static func fetchAndExtract(url: URL) async -> [Double]? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return extractHues(from: data)
    }

    /// Pure: decode image data, downsample, histogram dominant hues. Returns up
    /// to 3 well-separated hues, or nil if the art is near-grayscale.
    nonisolated static func extractHues(from data: Data) -> [Double]? {
        guard let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return extractHues(from: cg)
    }

    nonisolated static func extractHues(from cg: CGImage) -> [Double]? {
        let dim = 24
        var pixels = [UInt8](repeating: 0, count: dim * dim * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: dim, height: dim,
                                  bitsPerComponent: 8, bytesPerRow: dim * 4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: dim, height: dim))

        // Weighted hue histogram — 36 bins (10° each), weighted by
        // saturation × brightness so vivid pixels dominate and washed-out ones
        // barely register. Gray / near-black / near-white pixels are skipped.
        var bins = [Double](repeating: 0, count: 36)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255
            let g = Double(pixels[i + 1]) / 255
            let b = Double(pixels[i + 2]) / 255
            let (h, s, v) = rgbToHSV(r, g, b)
            if s < 0.22 || v < 0.18 || v > 0.97 { continue }
            bins[min(35, Int(h / 10))] += s * v
        }
        guard bins.contains(where: { $0 > 0 }) else { return nil }

        // Heaviest bins first, each ≥30° from those already chosen, so the
        // three hues read as distinct accents rather than one tight cluster.
        var chosen: [Double] = []
        for (bin, weight) in bins.enumerated().sorted(by: { $0.element > $1.element }) {
            guard weight > 0 else { break }
            let hue = Double(bin) * 10 + 5
            if chosen.allSatisfy({ hueDistance($0, hue) >= 30 }) {
                chosen.append(hue)
                if chosen.count == 3 { break }
            }
        }
        guard !chosen.isEmpty else { return nil }
        // Backdrop + procedural art expect exactly 3 hues; pad by rotating.
        while chosen.count < 3 {
            chosen.append((chosen[chosen.count - 1] + 50).truncatingRemainder(dividingBy: 360))
        }
        return chosen
    }

    nonisolated static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    private nonisolated static func rgbToHSV(_ r: Double, _ g: Double, _ b: Double)
        -> (h: Double, s: Double, v: Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = maxV - minV
        var h = 0.0
        if delta > 0 {
            if maxV == r { h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6)) }
            else if maxV == g { h = 60 * ((b - r) / delta + 2) }
            else { h = 60 * ((r - g) / delta + 4) }
        }
        if h < 0 { h += 360 }
        return (h, maxV == 0 ? 0 : delta / maxV, maxV)
    }
}
