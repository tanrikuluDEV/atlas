import Foundation
import Observation

enum GameMode: String, CaseIterable, Identifiable {
    case daily, practice
    var id: String { rawValue }
    var title: String { L("mode.\(rawValue)") }
}

enum GameStatus: String, Codable {
    case playing, won, lost
}

struct Guess: Identifiable, Hashable {
    let place: Place
    let distance: Int
    let order: Int
    var id: Int { place.id }
}

@Observable
final class GameModel {
    private let defaults = UserDefaults.standard

    private(set) var category: GameCategory
    private(set) var places: PlaceSet
    private(set) var mode: GameMode = .daily
    private(set) var answer: Place
    private(set) var guesses: [Guess] = []
    private(set) var status: GameStatus = .playing
    private(set) var dayIndex: Int
    private(set) var dailyStats = Stats()
    private(set) var practiceStats = Stats()

    /// Son yapılan geçerli tahmin; kenar çubuğunda geri bildirim olarak gösterilir.
    private(set) var lastGuess: Guess?
    /// Hata mesajı (bulunamayan ya da tekrar edilen tahmin).
    var message: String?
    /// Oyun bittiğinde sonuç penceresini açmak için.
    var showResult = false
    /// Tahmin listesinden seçilip haritada vurgulanan yer.
    var highlighted: Place?
    /// Her yeni turda artar; tahmin kutusu bunu izleyerek klavye odağını geri alır.
    private(set) var roundID = 0
    /// Bu turda açılan ipucu sayısı (en çok 3).
    private(set) var hintsUsed = 0
    /// Bu turda bitirilen oyunun kazandırdığı puan (sonuç penceresinde gösterilir).
    private(set) var reward: Reward?

    init() {
        let category = GameCategory(rawValue: UserDefaults.standard.string(forKey: "category") ?? "") ?? .turkey
        let today = DailyPuzzle.dayIndex(for: .now)
        self.category = category
        places = PlaceSet.forCategory(category)
        dayIndex = today
        answer = DailyPuzzle.answer(for: today, category: category)
        loadStats()
        restoreDaily()
    }

    // MARK: - Türetilmiş değerler

    var sortedGuesses: [Guess] {
        guesses.sorted { ($0.distance, $0.order) < ($1.distance, $1.order) }
    }

    var closest: Guess? { sortedGuesses.first }

    var isOver: Bool { status != .playing }

    var puzzleNumber: Int { dayIndex + 1 }

    var currentStats: Stats { mode == .daily ? dailyStats : practiceStats }

    func guess(for place: Place) -> Guess? {
        guesses.first { $0.place.id == place.id }
    }

    /// Gizli yer hakkındaki ipuçları (seçili dilde).
    var hints: [String] { Hints.hints(for: answer, in: category) }

    // MARK: - Eylemler

    @discardableResult
    func submit(_ text: String) -> Bool {
        guard !isOver else { return false }
        guard let place = places.match(text) else {
            message = L("msg.notFound.\(category.kind)", ["text": text.trimmingCharacters(in: .whitespaces)])
            return false
        }
        return submit(place)
    }

    @discardableResult
    func submit(_ place: Place) -> Bool {
        guard !isOver else { return false }
        if guess(for: place) != nil {
            message = L("msg.already", ["name": place.name])
            return false
        }
        let g = Guess(place: place, distance: places.distance(place, answer), order: guesses.count)
        guesses.append(g)
        lastGuess = g
        message = nil
        if place == answer {
            status = .won
            finish()
        }
        persistDaily()
        return true
    }

    func useHint() {
        guard !isOver, hintsUsed < hints.count else { return }
        hintsUsed += 1
        persistDaily()
    }

    func giveUp() {
        guard !isOver else { return }
        status = .lost
        message = nil
        finish()
        persistDaily()
    }

    func switchMode(_ newMode: GameMode) {
        guard newMode != mode else { return }
        mode = newMode
        if newMode == .daily {
            startDaily()
        } else {
            newPractice()
        }
    }

    func switchCategory(_ newCategory: GameCategory) {
        guard newCategory != category else { return }
        category = newCategory
        places = PlaceSet.forCategory(newCategory)
        defaults.set(newCategory.rawValue, forKey: "category")
        loadStats()
        if mode == .daily {
            startDaily()
        } else {
            newPractice()
        }
    }

    func newPractice() {
        mode = .practice
        var next = places.places.randomElement()!
        while next == answer { next = places.places.randomElement()! }
        answer = next
        resetRound()
    }

    /// Uygulama açıkken gün değiştiyse günlük bulmacayı yeniler.
    func refreshDayIfNeeded() {
        let today = DailyPuzzle.dayIndex(for: .now)
        guard today != dayIndex else { return }
        dailyStats.refreshStreak(today: today)
        dailyStats.save(key: Stats.key(category: category, mode: .daily))
        guard mode == .daily else { return }
        startDaily()
    }

    private func startDaily() {
        dayIndex = DailyPuzzle.dayIndex(for: .now)
        answer = DailyPuzzle.answer(for: dayIndex, category: category)
        restoreDaily()
    }

    private func resetRound() {
        guesses = []
        status = .playing
        message = nil
        lastGuess = nil
        showResult = false
        highlighted = nil
        hintsUsed = 0
        reward = nil
        roundID += 1
    }

    // MARK: - Kalıcılık

    private func loadStats() {
        var daily = Stats.load(key: Stats.key(category: category, mode: .daily))
        daily.refreshStreak(today: DailyPuzzle.dayIndex(for: .now))
        dailyStats = daily
        practiceStats = Stats.load(key: Stats.key(category: category, mode: .practice))
    }

    private func finish() {
        let won = status == .won
        let before = Progression.totalXP()
        switch mode {
        case .daily:
            dailyStats.recordDaily(won: won, guesses: guesses.count, hints: hintsUsed, answerID: answer.id, day: dayIndex)
            dailyStats.save(key: Stats.key(category: category, mode: .daily))
        case .practice:
            practiceStats.recordPractice(won: won, guesses: guesses.count, hints: hintsUsed, answerID: answer.id)
            practiceStats.save(key: Stats.key(category: category, mode: .practice))
        }
        reward = Reward(before: LevelProgress(xp: before), after: LevelProgress(xp: Progression.totalXP()))
        showResult = true
    }

    /// Türkiye için eski sürümle uyumlu anahtar korunur.
    private var dailyKey: String {
        category == .turkey ? "daily.\(dayIndex)" : "daily.\(category.rawValue).\(dayIndex)"
    }

    private func persistDaily() {
        guard mode == .daily else { return }
        let saved = SavedDaily(guessIDs: guesses.map(\.place.id), status: status, hints: hintsUsed)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: dailyKey) }
    }

    private func restoreDaily() {
        resetRound()
        guard let data = defaults.data(forKey: dailyKey),
              let saved = try? JSONDecoder().decode(SavedDaily.self, from: data) else { return }
        for id in saved.guessIDs {
            guard let p = places.place(id: id) else { continue }
            guesses.append(Guess(place: p, distance: places.distance(p, answer), order: guesses.count))
        }
        status = saved.status
        hintsUsed = saved.hints ?? 0
    }

    private struct SavedDaily: Codable {
        let guessIDs: [Int]
        let status: GameStatus
        /// Eski kayıtlarda yok.
        var hints: Int?
    }

    // MARK: - Paylaşım

    var shareText: String {
        let title = mode == .daily ? "Atlas #\(puzzleNumber) · \(category.title)" : "Atlas · \(category.title) (\(L("share.practice")))"
        // Renk bantları kategorinin ölçeğine göre: Türkiye'de 150 km yakın, dünyada ~1.800 km.
        let scale = Double(places.maxDistance)
        let squares = guesses.map { g -> String in
            if g.place == answer { return "🟩" }
            let t = Double(g.distance) / scale
            switch t {
            case 0: return "🟥"
            case ..<0.1: return "🟧"
            case ..<0.3: return "🟨"
            default: return "⬜️"
            }
        }.joined()
        var result = status == .won ? L("share.won", ["n": guesses.count]) : L("share.lost")
        if hintsUsed > 0 { result += " · " + L("share.hints", ["n": hintsUsed]) }
        return "\(title)\n\(result)\n\(squares)"
    }
}

enum DailyPuzzle {
    private static let epoch: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 1
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    static func dayIndex(for date: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: epoch)
        let today = cal.startOfDay(for: date)
        return max(0, cal.dateComponents([.day], from: start, to: today).day ?? 0)
    }

    /// Her döngüde kategorideki tüm yerler birer kez çıkar; döngü sırası sabit tohumla karıştırılır.
    static func answer(for day: Int, category: GameCategory) -> Place {
        // Türkiye'nin tohumu eski sürümle aynı kalır; böylece bugünün gizli ili değişmez.
        let salt = UInt64(GameCategory.allCases.firstIndex(of: category)!) &* 104_729
        let places = PlaceSet.forCategory(category).places.sorted { $0.id < $1.id }
        let cycle = day / places.count
        var rng = SeededGenerator(seed: UInt64(0xA71A5 &+ cycle &* 7919) &+ salt)
        let order = places.shuffled(using: &rng)
        return order[day % places.count]
    }
}

/// Deterministik karıştırma için SplitMix64.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
