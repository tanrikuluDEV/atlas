import SwiftUI

/// Kazanınca kısa bir konfeti yağmuru. Parçacıklar her karede kapalı formülle hesaplanır.
struct ConfettiView: View {
    let start: Date
    var duration: Double = 2.6

    private struct Particle {
        let x0, vx, vy, size, rot, vr: Double
        let color: Color
    }

    private static let colors: [Color] = [
        Color(red: 0.18, green: 0.62, blue: 0.31), Color(red: 0.95, green: 0.76, blue: 0.31),
        Color(red: 0.89, green: 0.22, blue: 0.18), Color(red: 0.04, green: 0.52, blue: 1),
        Color(red: 0.58, green: 0.24, blue: 0.96), Color(red: 1, green: 0.55, blue: 0.26),
    ]

    private let particles: [Particle] = (0..<140).map { _ in
        Particle(x0: Double.random(in: -0.15...0.15), vx: Double.random(in: -7...7), vy: -6 - Double.random(in: 0...10),
                 size: 5 + Double.random(in: 0...6), rot: Double.random(in: 0...(.pi)), vr: Double.random(in: -0.15...0.15),
                 color: colors.randomElement()!)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < duration else { return }
                // 60 kare/sn'lik adımlarla: hız sönümü 0,99, yerçekimi 0,32.
                let n = t * 60
                let damp = (1 - pow(0.99, n)) / 0.01
                ctx.opacity = max(0, 1 - max(0, t - duration * 0.6) / (duration * 0.4))
                for p in particles {
                    let x = size.width / 2 + p.x0 * size.width + p.vx * damp
                    let y = size.height * 0.35 + p.vy * n + 0.32 * n * (n + 1) / 2
                    guard y < size.height + 20 else { continue }
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.rot + p.vr * n))
                    c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
