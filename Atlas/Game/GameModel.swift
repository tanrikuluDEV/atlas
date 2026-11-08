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
    /// Bu oyunla kazanılan yeni rozetler (sonuç penceresinde gösterilir).
    private(set) var newBadges: [Badge] = []
    /// Son tahmin, önceki en yakın tahminden daha yakın mı (sıcaklık göstergesi, ses ve titreşim için).
    private(set) var lastImproved = false
    /// Rota tekrarı: nil değilse haritada yalnızca ilk `replayStep` tahmin görünür
    /// (pes edilen oyunda son adım gizli yeri gösterir).
    private(set) var replayStep: Int?
    private var replayTask: Task<Void, Never>?
    /// Bu turun uzman modu, ilk tahminde ayardan alınıp sabitlenir (tur ortasında ayar değişse de değişmez).
    private var roundExpert: Bool?

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

    /// Uzman modu: haritada adlar ve mesafeler gizli, yalnızca renk. Tur başlamadan ayar değişirse hemen uyar.
    var expert: Bool { roundExpert ?? GameSettings.shared.expert }

    /// Mesafe kilometre olarak gösterilsin mi (ayar açık ve uzman modu kapalı).
    func showsKm(_ setting: Bool) -> Bool { setting && !expert }

    /// Haritada tahmin edilen yerlerin adları yazılsın mı (uzman modunda oyun bitene kadar yazılmaz).
    var showsGuessNames: Bool { !expert || isOver }

    /// Rota tekrarının adım sayısı: tahminler, pes edildiyse bir de gizli yer.
    var replayLength: Int { guesses.count + (status == .lost ? 1 : 0) }

    /// Haritada görünen tahmin (rota tekrarında henüz sırası gelmemiş tahminler gizlenir).
    func mapGuess(for place: Place) -> Guess? {
        guard let g = guess(for: place) else { return nil }
        if let step = replayStep, g.order >= step { return nil }
        return g
    }

    /// Haritada gizli yer açık mı (oyun bittiyse ve rota tekrarı sona geldiyse).
    var mapRevealsAnswer: Bool {
        isOver && (replayStep.map { $0 >= replayLength } ?? true)
    }

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
        if roundExpert == nil { roundExpert = GameSettings.shared.expert }
        let g = Guess(place: place, distance: places.distance(place, answer), order: guesses.count)
        lastImproved = guesses.isEmpty || g.distance < (closest?.distance ?? .max)
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
        if roundExpert == nil { roundExpert = GameSettings.shared.expert }
        status = .lost
        message = nil
        finish()
        persistDaily()
    }

    /// Bugünün günlük bulmacası bitmemiş kategoriler (oyun sonundaki kısayollar için).
    static func unfinishedDailies(day: Int) -> [GameCategory] {
        GameCategory.allCases.filter { c in
            guard let saved = savedDaily(category: c, day: day) else { return true }
            return saved.status == .playing
        }
    }

    /// Bir sonraki günlük bulmacaya (yerel gece yarısı) kalan süre.
    static func timeUntilNextPuzzle(from now: Date = .now) -> TimeInterval {
        let cal = Calendar(identifier: .gregorian)
        let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        return max(0, next.timeIntervalSince(now))
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

    // MARK: - Rota tekrarı

    /// Tahminleri sırasıyla haritada yeniden oynatır; harita her adımda o yere uçar ve parlar.
    func startReplay() {
        guard isOver, replayLength > 0 else { return }
        stopReplay()
        let total = replayLength
        // Uzun oyunlarda adımlar kısalır; tekrar en fazla ~12 sn sürer.
        let interval = max(0.45, min(1.1, 12 / Double(total)))
        replayStep = 0
        replayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.7))
            for step in 1...total {
                guard let self, !Task.isCancelled else { return }
                self.replayStep = step
                try? await Task.sleep(for: .seconds(step == total ? 2.6 : interval))
            }
            guard let self, !Task.isCancelled else { return }
            self.replayStep = nil
        }
    }

    func stopReplay() {
        replayTask?.cancel()
        replayTask = nil
        replayStep = nil
    }

    /// Rota tekrarında o adımda gösterilen yer.
    func replayPlace(at step: Int) -> Place? {
        guard step >= 1 else { return nil }
        let ordered = guesses.sorted { $0.order < $1.order }
        return step <= ordered.count ? ordered[step - 1].place : answer
    }

    private func resetRound() {
        stopReplay()
        newBadges = []
        lastImproved = false
        guesses = []
        status = .playing
        message = nil
        lastGuess = nil
        showResult = false
        highlighted = nil
        hintsUsed = 0
        reward = nil
        roundExpert = nil
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
        let badgesBefore = Badges.earnedIDs()
        switch mode {
        case .daily:
            dailyStats.recordDaily(won: won, guesses: guesses.count, hints: hintsUsed, answerID: answer.id, day: dayIndex,
                                   expert: expert)
            dailyStats.save(key: Stats.key(category: category, mode: .daily))
        case .practice:
            practiceStats.recordPractice(won: won, guesses: guesses.count, hints: hintsUsed, answerID: answer.id,
                                         expert: expert)
            practiceStats.save(key: Stats.key(category: category, mode: .practice))
        }
        reward = Reward(before: LevelProgress(xp: before), after: LevelProgress(xp: Progression.totalXP()))
        newBadges = Badges.all().filter { $0.earned && !badgesBefore.contains($0.id) }
        showResult = true
    }

    /// Türkiye için eski sürümle uyumlu anahtar korunur.
    private var dailyKey: String { Self.dailyKey(category: category, day: dayIndex) }

    private static func dailyKey(category: GameCategory, day: Int) -> String {
        category == .turkey ? "daily.\(day)" : "daily.\(category.rawValue).\(day)"
    }

    /// Bir kategorinin o günkü günlük bulmacası: durum ve tahmin sayısı (kategori seçicideki rozet için).
    static func savedDaily(category: GameCategory, day: Int) -> (status: GameStatus, guesses: Int)? {
        guard let data = UserDefaults.standard.data(forKey: dailyKey(category: category, day: day)),
              let saved = try? JSONDecoder().decode(SavedDaily.self, from: data) else { return nil }
        return (saved.status, saved.guessIDs.count)
    }

    private func persistDaily() {
        guard mode == .daily else { return }
        let saved = SavedDaily(guessIDs: guesses.map(\.place.id), status: status, hints: hintsUsed, expert: roundExpert)
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
        // Başlamış bir turun uzman modu kayıttan gelir (eski kayıtlar normal mod).
        if !guesses.isEmpty || status != .playing { roundExpert = saved.expert ?? false }
    }

    private struct SavedDaily: Codable {
        let guessIDs: [Int]
        let status: GameStatus
        /// Eski kayıtlarda yok.
        var hints: Int?
        var expert: Bool?
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
        if expert { result += " · " + L("share.expert") }
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
        let salt = UInt64(category.seedIndex) &* 104_729
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
