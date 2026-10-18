import SwiftUI

/// Globle tarzı sıcaklık skalası: yakın = koyu kırmızı, uzak = soluk krem.
enum ColorScale {
    static let found = Color(red: 0.18, green: 0.62, blue: 0.31)
    static let answerReveal = Color(red: 0.16, green: 0.45, blue: 0.85)
    /// Listeden seçilen yerin vurgusu; sıcaklık renkleriyle karışmasın diye mor.
    static let highlight = Color(red: 0.58, green: 0.24, blue: 0.96)

    private static let stops: [(Double, Double, Double)] = [
        (0.45, 0.00, 0.06), // komşu
        (0.72, 0.07, 0.12),
        (0.93, 0.30, 0.14),
        (0.99, 0.55, 0.24),
        (1.00, 0.76, 0.45),
        (1.00, 0.90, 0.72),
        (1.00, 0.96, 0.89), // en uzak
    ]

    static func color(forDistance km: Int, max maxKm: Int) -> Color {
        // Karekök ile yakın mesafelerdeki farklar daha belirgin olur.
        let t = min(1, max(0, sqrt(Double(km) / Double(max(maxKm, 1)))))
        let scaled = t * Double(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        let f = scaled - Double(i)
        let a = stops[i], b = stops[i + 1]
        return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
    }
}
