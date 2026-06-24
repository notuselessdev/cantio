import AVFoundation
import AppKit

/// A soft, rising three-note chime played once when onboarding reveals.
///
/// Synthesized at runtime — no bundled audio asset — so it stays inside the
/// privacy/no-extra-resources posture. Three ascending partials of a C-major
/// triad (C5 → E5 → G5), each with a raised-cosine envelope and a slight
/// overlap so the gesture reads as a single upward sweep rather than three
/// separate beeps. Output rides system volume via the engine's main mixer.
@MainActor
final class OnboardingChime {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode,
                       format: engine.mainMixerNode.outputFormat(forBus: 0))
    }

    /// Play once. No-ops if the buffer can't be built or the engine refuses to
    /// start (e.g. no output device) — the chime is a flourish, never a gate.
    func play() {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        guard let buffer = Self.makeBuffer(format: format) else { return }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor in self?.engine.stop() }
        }
        player.play()
    }

    private static func makeBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return nil }
        let duration = 1.5
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount

        // (frequency, onset, duration) — C5, E5, G5, each fading in/out.
        let notes: [(freq: Double, start: Double, dur: Double)] = [
            (523.25, 0.00, 0.75),
            (659.25, 0.16, 0.78),
            (783.99, 0.32, 0.95),
        ]
        let gain = 0.16

        let mono = channels[0]
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            var sample = 0.0
            for note in notes {
                let local = t - note.start
                guard local >= 0, local <= note.dur else { continue }
                // Raised-cosine envelope: 0 → 1 → 0 over the note's life.
                let env = 0.5 - 0.5 * cos(2 * .pi * (local / note.dur))
                sample += sin(2 * .pi * note.freq * local) * env * gain
            }
            mono[frame] = Float(sample)
        }
        // Mirror into any remaining channels (stereo output is the common case).
        for ch in 1..<Int(format.channelCount) {
            memcpy(channels[ch], mono, Int(frameCount) * MemoryLayout<Float>.size)
        }
        return buffer
    }
}
