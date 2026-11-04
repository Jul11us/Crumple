import AVFoundation
import AppKit

/// The paper's sounds, made from noise and a few tones when first needed (no audio files),
/// plus a light trackpad tap for the moments that land. Off when 声音和触感 is switched off.
@MainActor
final class SoundBoard {
    static let shared = SoundBoard()

    enum Sound: CaseIterable {
        case crumple, swish, clank, shred, pour, unfold
    }

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "playsSounds") as? Bool ?? true }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundBoard.rate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [Sound: Double] = [:]
    private var nextPlayer = 0
    private var started = false
    nonisolated private static let rate = 44_100.0

    func play(_ sound: Sound, volume: Float = 1) {
        guard isEnabled else { return }
        // A batch clean throws many balls at once; a few overlapping sounds are enough.
        let now = Date.timeIntervalSinceReferenceDate
        if let last = lastPlayed[sound], now - last < 0.07 { return }
        lastPlayed[sound] = now
        guard start() else { return }
        let buffer = buffers[sound] ?? makeBuffer(sound)
        buffers[sound] = buffer
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        haptic(for: sound)
    }

    private func start() -> Bool {
        if started { return true }
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        do {
            try engine.start()
            started = true
        } catch {
            return false
        }
        return true
    }

    private func haptic(for sound: Sound) {
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch sound {
        case .swish, .shred, .pour: pattern = .generic
        case .clank: pattern = .alignment
        case .crumple, .unfold: return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    // MARK: - Making the sounds

    private func makeBuffer(_ sound: Sound) -> AVAudioPCMBuffer {
        let samples = Self.synthesize(sound)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }

    nonisolated static func synthesize(_ sound: Sound) -> [Float] {
        var rng = SeededRandom(UInt64(Sound.allCases.firstIndex(of: sound)! + 11))
        func noise() -> Float { Float(rng.range(-1, 1)) }
        func samples(_ seconds: Double, _ make: (Double, Double) -> Float) -> [Float] {
            let count = Int(seconds * rate)
            return (0..<count).map { make(Double($0) / rate, Double($0) / Double(count)) }
        }
        /// Paper: little cracks over a hiss, high-passed so it stays crisp.
        func paper(_ seconds: Double, crackRate: Double, level: Float) -> [Float] {
            var crack: Float = 0
            var raw = samples(seconds) { _, p in
                if Double(rng.unit()) < crackRate { crack = Float(rng.range(0.4, 1)) }
                crack *= 0.986
                let envelope = Float(pow(sin(.pi * p), 0.6))
                return (crack * noise() + 0.05 * noise()) * envelope * level
            }
            var previous: Float = 0, out: Float = 0
            for i in raw.indices {
                out = raw[i] - previous + 0.95 * out
                previous = raw[i]
                raw[i] = out
            }
            return raw
        }

        var out: [Float]
        switch sound {
        case .crumple:
            out = paper(0.32, crackRate: 0.0028, level: 0.6)
        case .unfold:
            out = paper(0.45, crackRate: 0.0014, level: 0.35)
        case .swish:
            // Air through the net, then the soft bump of the ball landing.
            var low: Float = 0
            out = samples(0.3) { t, p in
                let cutoff = Float(0.04 + 0.22 * sin(.pi * p))
                low += cutoff * (noise() - low)
                let air = low * Float(pow(sin(.pi * min(1, p * 1.25)), 2)) * 1.6
                let bump = t > 0.2 ? Float(sin(2 * .pi * 72 * (t - 0.2)) * exp(-(t - 0.2) / 0.05)) * 0.55 : 0
                return air + bump
            }
        case .clank:
            // A wire rim being hit: a few inharmonic partials that ring out.
            let partials: [(Double, Double)] = [(430, 0.5), (1090, 0.35), (1720, 0.25), (2610, 0.15)]
            out = samples(0.4) { t, _ in
                let attack = min(1, t / 0.002)
                return Float(partials.enumerated().reduce(0.0) { sum, item in
                    let (i, (frequency, amplitude)) = item
                    return sum + amplitude * sin(2 * .pi * frequency * t) * exp(-t / (0.11 / (1 + Double(i) * 0.5)))
                } * attack * 0.6)
            }
        case .shred:
            // A small motor and paper being cut.
            var low: Float = 0
            var crack: Float = 0
            out = samples(0.7) { t, p in
                let motor = Float(2 * ((95 * t).truncatingRemainder(dividingBy: 1)) - 1) * 0.3
                if Double(rng.unit()) < 0.004 { crack = Float(rng.range(0.3, 0.8)) }
                crack *= 0.98
                low += 0.35 * (motor + crack * noise() - low)
                let envelope = Float(min(1, t / 0.03) * min(1, (1 - p) / 0.18))
                return low * envelope * 1.2
            }
        case .pour:
            // Paper sliding out and balls dropping one after another.
            var low: Float = 0
            let drops = (0..<7).map { _ in Double(rng.range(0.15, 0.8)) }
            out = samples(0.95) { t, p in
                low += 0.15 * (noise() - low)
                let slide = low * Float(sin(.pi * p)) * 0.8
                let thuds = drops.reduce(0.0) { sum, start in
                    t > start ? sum + sin(2 * .pi * 95 * (t - start)) * exp(-(t - start) / 0.04) : sum
                }
                return slide + Float(thuds) * 0.35
            }
        }
        let peak = out.map(abs).max() ?? 1
        let gain = peak > 0 ? 0.8 / peak : 1
        return out.map { $0 * gain }
    }
}
