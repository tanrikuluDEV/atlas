import Foundation

/// Bitirilen tek bir oyunun kaydı; gelişim grafiği bunlardan çizilir.
struct GameRecord: Codable, Identifiable, Hashable {
    let date: Date
    let guesses: Int
    let won: Bool
    let answerID: Int
    /// Açılan ipucu sayısı (puan hesabı için); bu alandan önceki kayıtlarda yok.
    var hints: Int?
    var id: Date { date }
}

/// Günlük ve alıştırma oyunları ayrı `Stats` kayıtlarında tutulur.
struct Stats: Codable {
    var played = 0
    var won = 0
    var currentStreak = 0
    var maxStreak = 0
    var lastWonDay: Int?
    var lastPlayedDay: Int?
    /// Kazanılan her oyundaki tahmin sayısı.
    var winningGuessCounts: [Int] = []
    /// Oyun geçmişi (eskiden yeniye). Bu özellikten önce oynanan oyunlar burada yok.
    var history: [GameRecord] = []

    init() {}

    // Eski sürümlerin kaydettiği veride bulunmayan alanlar varsayılan değerle okunur.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        played = try c.decodeIfPresent(Int.self, forKey: .played) ?? 0
        won = try c.decodeIfPresent(Int.self, forKey: .won) ?? 0
        currentStreak = try c.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        maxStreak = try c.decodeIfPresent(Int.self, forKey: .maxStreak) ?? 0
        lastWonDay = try c.decodeIfPresent(Int.self, forKey: .lastWonDay)
        lastPlayedDay = try c.decodeIfPresent(Int.self, forKey: .lastPlayedDay)
        winningGuessCounts = try c.decodeIfPresent([Int].self, forKey: .winningGuessCounts) ?? []
        history = try c.decodeIfPresent([GameRecord].self, forKey: .history) ?? []
    }

    /// Türkiye için eski sürümdeki anahtarlar korunur, böylece mevcut istatistikler kaybolmaz.
    static func key(category: GameCategory, mode: GameMode) -> String {
        let base = mode == .daily ? "stats" : "stats.practice"
        return category == .turkey ? base : "\(base).\(category.rawValue)"
    }

    var winRate: Int { played == 0 ? 0 : Int((Double(won) / Double(played) * 100).rounded()) }

    var averageGuesses: Double? {
        winningGuessCounts.isEmpty ? nil : Double(winningGuessCounts.reduce(0, +)) / Double(winningGuessCounts.count)
    }

    /// Son `count` kazanılan oyundaki ortalama tahmin.
    func recentAverage(last count: Int) -> Double? {
        let recent = history.filter(\.won).suffix(count)
        return recent.isEmpty ? nil : Double(recent.map(\.guesses).reduce(0, +)) / Double(recent.count)
    }

    /// Tahmin sayısı dağılımı: 1-3, 4-6, 7-10, 11-15, 16+
    var distribution: [(label: String, count: Int)] {
        let buckets: [(String, ClosedRange<Int>)] = [("1–3", 1...3), ("4–6", 4...6), ("7–10", 7...10), ("11–15", 11...15), ("16+", 16...Int.max)]
        return buckets.map { label, range in (label, winningGuessCounts.filter { range.contains($0) }.count) }
    }

    /// Günlük oyun: aynı gün bir kez sayılır, seri art arda günlerle ilerler.
    mutating func recordDaily(won didWin: Bool, guesses: Int, hints: Int, answerID: Int, day: Int) {
        guard lastPlayedDay != day else { return }
        lastPlayedDay = day
        played += 1
        history.append(GameRecord(date: .now, guesses: guesses, won: didWin, answerID: answerID, hints: hints))
        if didWin {
            won += 1
            winningGuessCounts.append(guesses)
            currentStreak = (lastWonDay == day - 1) ? currentStreak + 1 : 1
            maxStreak = max(maxStreak, currentStreak)
            lastWonDay = day
        } else {
            currentStreak = 0
        }
    }

    /// Alıştırma: her oyun sayılır, seri art arda kazanılan oyun sayısıdır.
    mutating func recordPractice(won didWin: Bool, guesses: Int, hints: Int, answerID: Int) {
        played += 1
        history.append(GameRecord(date: .now, guesses: guesses, won: didWin, answerID: answerID, hints: hints))
        if didWin {
            won += 1
            winningGuessCounts.append(guesses)
            currentStreak += 1
            maxStreak = max(maxStreak, currentStreak)
        } else {
            currentStreak = 0
        }
    }

    /// Bir gün atlandıysa seri sıfırlanır.
    mutating func refreshStreak(today: Int) {
        if let last = lastWonDay, last < today - 1 { currentStreak = 0 }
    }

    static func load(key: String) -> Stats {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Stats.self, from: data) else { return Stats() }
        return s
    }

    func save(key: String) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: key) }
    }
}
