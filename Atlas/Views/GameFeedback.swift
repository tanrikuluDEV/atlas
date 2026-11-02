import AVFoundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Tahminlerde kısa sesler (isteğe bağlı, varsayılan kapalı) ve iPhone'da titreşim (varsayılan açık).
/// Sesler dosyadan değil, anında üretilen kısa tonlardan oluşur. Web karşılığı `web/js/feedback.js`.
@MainActor
final class GameFeedback {
    static let shared = GameFeedback()

    static let soundKey = "sound"
    static let hapticsKey = "haptics"

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var ready = false

    private var soundOn: Bool { UserDefaults.standard.bool(forKey: Self.soundKey) }
    private var hapticsOn: Bool { UserDefaults.standard.object(forKey: Self.hapticsKey) as? Bool ?? true }

    /// Yakınlık 0…1 (1 = komşu). Ton yaklaştıkça incelir; öncekinden yakınsa ikinci, daha ince bir nota eklenir.
    func guessMade(proximity: Double, improved: Bool) {
        let f = 330 * pow(2, proximity * 1.5)
        var notes: [Note] = [Note(freq: f, start: 0, length: 0.16)]
        if improved { notes.append(Note(freq: f * 1.26, start: 0.09, length: 0.2)) }
        play(notes, volume: 0.22)
        #if os(iOS)
        if hapticsOn && improved {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5 + 0.5 * proximity)
        }
        #endif
    }

    func won() {
        // Do–mi–sol–do arpeji.
        play([523.25, 659.25, 783.99, 1046.5].enumerated().map { Note(freq: $1, start: Double($0) * 0.09, length: 0.5) },
             volume: 0.2)
        #if os(iOS)
        if hapticsOn {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
        #endif
    }

    func lost() {
        play([Note(freq: 392, start: 0, length: 0.22), Note(freq: 293.66, start: 0.16, length: 0.4)], volume: 0.18)
        #if os(iOS)
        if hapticsOn { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        #endif
    }

    // MARK: - Ses üretimi

    private struct Note {
        let freq: Double
        let start: Double
        let length: Double
    }

    private func play(_ notes: [Note], volume: Float) {
        guard soundOn, prepare() else { return }
        let rate = format.sampleRate
        let total = (notes.map { $0.start + $0.length }.max() ?? 0) + 0.02
        let frames = AVAudioFrameCount(total * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { data[i] = 0 }
        for note in notes {
            let first = Int(note.start * rate), count = Int(note.length * rate)
            for j in 0..<count where first + j < Int(frames) {
                let t = Double(j) / rate
                // Hızlı yükselme, üstel sönüm; hafif bir üst ton sesi yumuşatır.
                let env = min(1, t / 0.006) * exp(-t * 7 / note.length)
                let wave = sin(2 * .pi * note.freq * t) + 0.25 * sin(4 * .pi * note.freq * t)
                data[first + j] += Float(wave * env) * volume
            }
        }
        player.scheduleBuffer(buffer, at: nil)
        if !player.isPlaying { player.play() }
    }

    private func prepare() -> Bool {
        #if os(iOS) || os(tvOS)
        // "TV'ye söyle" kayıt oturumunu bozmamak için yalnızca başka bir ses oturumu yokken ayarlanır;
        // `ambient` sessiz modu dinler ve diğer seslerle karışır.
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try? session.setCategory(.ambient)
            try? session.setActive(true)
        }
        #endif
        if !ready {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            ready = true
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        return true
    }
}
