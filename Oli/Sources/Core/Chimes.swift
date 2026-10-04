import AVFoundation

// MARK: - Sons d'Oli
// Synthesized at launch (soft marimba-like notes), no audio files. Each cue is a short melody.
// `alarm` plays at full volume whatever the slider, to be heard across the room.

enum Cue: String, CaseIterable {
    case unfold, fold, tick, attention, done, alarm, back

    /// (frequency Hz, start s, length s) — notes of the cue.
    fileprivate var notes: [(Double, Double, Double)] {
        switch self {
        case .unfold:    return [(659.3, 0, 0.16), (987.8, 0.07, 0.22)]                       // mi → si
        case .fold:      return [(880.0, 0, 0.14), (587.3, 0.06, 0.2)]                        // la → ré
        case .tick:      return [(1318.5, 0, 0.06)]
        case .attention: return [(784.0, 0, 0.16), (1046.5, 0.12, 0.16), (784.0, 0.26, 0.24)] // sol do sol
        case .done:      return [(523.3, 0, 0.18), (659.3, 0.09, 0.18), (784.0, 0.18, 0.18), (1046.5, 0.27, 0.34)]
        case .alarm:     return [(1174.7, 0, 0.18), (880.0, 0.2, 0.18), (1174.7, 0.4, 0.18), (880.0, 0.6, 0.18),
                                 (1174.7, 0.8, 0.18), (880.0, 1.0, 0.3)]
        case .back:      return [(587.3, 0, 0.16), (880.0, 0.1, 0.26)]
        }
    }
    fileprivate var bright: Bool { self == .alarm }
}

@MainActor
final class Chimes {
    static let shared = Chimes()
    private var players: [Cue: AVAudioPlayer] = [:]
    var volume: Float = 0.35

    private init() {
        for cue in Cue.allCases {
            if let p = try? AVAudioPlayer(data: Self.render(cue)) { p.prepareToPlay(); players[cue] = p }
        }
    }

    func play(_ cue: Cue) {
        guard OliModel.shared.soundOn, let p = players[cue] else { return }
        p.currentTime = 0
        p.volume = cue == .alarm ? 1.0 : volume
        p.play()
    }

    // MARK: Synthesis → 16-bit mono WAV in memory

    private static let rate = 44_100.0

    private static func render(_ cue: Cue) -> Data {
        let notes = cue.notes
        let total = (notes.map { $0.1 + $0.2 }.max() ?? 0.2) + 0.25
        var buf = [Double](repeating: 0, count: Int(total * rate))
        for (f, start, len) in notes {
            let s0 = Int(start * rate), n = Int((len + 0.2) * rate)
            for i in 0..<n where s0 + i < buf.count {
                let t = Double(i) / rate
                let env = min(1, t / 0.004) * exp(-t / (len * 0.55))
                // marimba-ish: fundamental + soft 4th harmonic; the alarm gets an odd harmonic bite
                var v = sin(2 * .pi * f * t) + 0.18 * sin(2 * .pi * f * 4 * t) * exp(-t / 0.03)
                if cue.bright { v += 0.35 * sin(2 * .pi * f * 3 * t) }
                buf[s0 + i] += v * env
            }
        }
        let peak = max(buf.map(abs).max() ?? 1, 0.0001)
        let samples = buf.map { Int16(max(-1, min(1, $0 / peak * 0.9)) * 32_000) }
        return wav(samples)
    }

    private static func wav(_ s: [Int16]) -> Data {
        var d = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(s.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36) + bytes)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate) * 2); put(UInt16(2)); put(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); put(bytes)
        s.forEach { put($0) }
        return d
    }
}
