import Foundation

/// Puan (XP) ve seviyeler. Web karşılığı `web/js/progression.js`; formüller birebir aynı olmalı.
///
/// Yalnızca kazanılan oyun puan getirir:
/// - Taban puan tahmin sayısına göre: 1 → 200, 2 → 150, 3 → 120, sonra her tahminde 10 eksik (en az 20).
/// - Günlük bulmaca ×1,5 (günde bir kez oynanır); kategori zorluğu ×0,6–1,5; her ipucu −%15.
/// - Sonuç 5'in katına yuvarlanır.
///
/// Seviye L'ye ulaşmak için toplam 125·L·(L−1) XP gerekir (2 → 250, 5 → 2.500, 10 → 11.250).
/// Toplam XP ayrıca saklanmaz; tüm kategorilerin oyun geçmişinden hesaplanır.
enum Progression {
    static func basePoints(guesses: Int) -> Double {
        switch guesses {
        case 1: 200
        case 2: 150
        case 3: 120
        default: Double(max(20, 150 - 10 * guesses))
        }
    }

    static func categoryFactor(_ category: GameCategory) -> Double {
        switch category {
        case .world: 1.5
        case .turkey: 1.2
        case .europe, .asia, .africa: 1
        case .northAmerica: 0.8
        case .southAmerica, .oceania: 0.6
        }
    }

    static func points(guesses: Int, hints: Int, category: GameCategory, mode: GameMode) -> Int {
        let hintFactor = 1 - 0.15 * Double(min(max(hints, 0), 3))
        let modeFactor = mode == .daily ? 1.5 : 1
        let raw = basePoints(guesses: guesses) * hintFactor * categoryFactor(category) * modeFactor
        return Int((raw / 5).rounded()) * 5
    }

    /// Seviye L'nin başladığı toplam XP.
    static func threshold(level: Int) -> Int { 125 * level * (level - 1) }

    static func level(xp: Int) -> Int {
        var level = Int((125 + (15_625 + 500 * Double(xp)).squareRoot()) / 250)
        // Kayan nokta hatasına karşı sınırda düzelt.
        while threshold(level: level + 1) <= xp { level += 1 }
        while level > 1 && threshold(level: level) > xp { level -= 1 }
        return max(level, 1)
    }

    /// Bir kategori/mod geçmişindeki puanlar. Geçmiş özelliğinden önce kazanılan oyunlar yalnızca
    /// `winningGuessCounts`'ta var; onlar ipucusuz sayılır.
    static func xp(of stats: Stats, category: GameCategory, mode: GameMode) -> Int {
        let recordedWins = stats.history.filter(\.won)
        let older = stats.winningGuessCounts.dropLast(recordedWins.count)
        var total = 0
        for guesses in older {
            total += points(guesses: guesses, hints: 0, category: category, mode: mode)
        }
        for record in recordedWins {
            total += points(guesses: record.guesses, hints: record.hints ?? 0, category: category, mode: mode)
        }
        return total
    }

    static func totalXP() -> Int {
        var total = 0
        for category in GameCategory.allCases {
            for mode in GameMode.allCases {
                total += xp(of: Stats.load(key: Stats.key(category: category, mode: mode)), category: category, mode: mode)
            }
        }
        return total
    }
}

/// Seviye ilerlemesi: toplam XP'den türetilir.
struct LevelProgress: Equatable {
    let xp: Int

    var level: Int { Progression.level(xp: xp) }
    var start: Int { Progression.threshold(level: level) }
    var next: Int { Progression.threshold(level: level + 1) }
    /// Mevcut seviyede ilerleme (0…1).
    var fraction: Double { Double(xp - start) / Double(next - start) }
}

/// Bitirilen oyunun kazandırdığı puan.
struct Reward: Equatable {
    let before: LevelProgress
    let after: LevelProgress

    var gained: Int { after.xp - before.xp }
    var leveledUp: Bool { after.level > before.level }
}
