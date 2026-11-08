import Foundation

// Zamana karşı ve komşu zinciri modlarının kayıtları ve zincirin komşuluk grafiği.
// Web karşılığı `web/js/modes.js` (aynı kurallar, aynı puanlar).

// MARK: - Zamana karşı

/// Zamana karşı: 3 dakikada bulunabildiği kadar yer. Kategori başına en iyi skor ve geçmiş.
struct TimedStats: Codable {
    struct Run: Codable, Hashable {
        let date: Date
        let score: Int
        let skipped: Int
    }

    var best = 0
    var runs: [Run] = []

    static func key(_ category: GameCategory) -> String { "timed.\(category.rawValue)" }

    static func load(_ category: GameCategory) -> TimedStats {
        guard let data = UserDefaults.standard.data(forKey: key(category)),
              let s = try? JSONDecoder().decode(TimedStats.self, from: data) else { return TimedStats() }
        return s
    }

    func save(_ category: GameCategory) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key(category)) }
    }

    mutating func record(score: Int, skipped: Int) {
        runs.append(Run(date: .now, score: score, skipped: skipped))
        best = max(best, score)
    }
}

/// Bitmiş bir zamana karşı turunun özeti (sonuç penceresi için).
struct TimedResult: Equatable {
    let score: Int
    let best: Int
    let isRecord: Bool
}

// MARK: - Komşu zinciri

/// Komşu zinciri: başlangıçtan bitişe komşu yerlerden bir rota. Kategori başına geçmiş.
struct ChainStats: Codable {
    struct Run: Codable, Hashable {
        let date: Date
        let won: Bool
        let guesses: Int
        /// En kısa rotadaki ara yer sayısı.
        let optimal: Int
    }

    var runs: [Run] = []

    var played: Int { runs.count }
    var won: Int { runs.filter(\.won).count }
    var perfect: Int { runs.filter { $0.won && $0.guesses == $0.optimal }.count }

    static func key(_ category: GameCategory) -> String { "chain.\(category.rawValue)" }

    static func load(_ category: GameCategory) -> ChainStats {
        guard let data = UserDefaults.standard.data(forKey: key(category)),
              let s = try? JSONDecoder().decode(ChainStats.self, from: data) else { return ChainStats() }
        return s
    }

    func save(_ category: GameCategory) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key(category)) }
    }
}

/// Zincirde bir tahminin rotaya göre durumu.
enum ChainClass: Int {
    /// En kısa rotalardan birinin üstünde.
    case onPath = 0
    /// En kısa rotadan 1–2 adım sapıyor.
    case near = 1
    /// Uzak ya da başlangıca hiç bağlanmıyor (ada).
    case far = 2
}

extension PlaceSet {
    private static var neighborCache: [GameCategory: [Int: [Place]]] = [:]

    /// Kara sınırı olan komşular (mesafe 0).
    var neighbors: [Int: [Place]] {
        if let cached = Self.neighborCache[category] { return cached }
        var result: [Int: [Place]] = [:]
        for a in places {
            result[a.id] = places.filter { $0 != a && distance(a, $0) == 0 }
        }
        Self.neighborCache[category] = result
        return result
    }

    /// Bir yerden diğerlerine kaç komşu adımı olduğu (ulaşılamayanlar yok).
    func hopDistances(from start: Place) -> [Int: Int] {
        let graph = neighbors
        var dist = [start.id: 0]
        var queue = [start]
        var i = 0
        while i < queue.count {
            let p = queue[i]; i += 1
            for n in graph[p.id] ?? [] where dist[n.id] == nil {
                dist[n.id] = dist[p.id]! + 1
                queue.append(n)
            }
        }
        return dist
    }

    /// Yalnızca `allowed` içindeki yerlerden geçen en kısa rota (uçlar dahil); yoksa nil.
    func shortestPath(from start: Place, to end: Place, through allowed: Set<Int>? = nil) -> [Place]? {
        let graph = neighbors
        var parent: [Int: Place] = [:]
        var seen: Set<Int> = [start.id]
        var queue = [start]
        var i = 0
        while i < queue.count {
            let p = queue[i]; i += 1
            if p == end {
                var path = [end]
                while let prev = parent[path[0].id] { path.insert(prev, at: 0) }
                return path
            }
            for n in graph[p.id] ?? [] where !seen.contains(n.id) && (n == end || allowed?.contains(n.id) ?? true) {
                seen.insert(n.id)
                parent[n.id] = p
                queue.append(n)
            }
        }
        return nil
    }

    /// Zincir için uygun adım aralığı (kenar sayısı): ara yer sayısı bunun bir eksiği.
    private var chainHops: ClosedRange<Int> {
        switch category {
        case .turkey: 4...7
        case .southAmerica: 3...5
        default: 3...6
        }
    }

    /// Bu kategoride zincir kurulabilir mi (en az üç adımlık bir rota var mı).
    var supportsChain: Bool { chainPairExists }

    private static var chainSupportCache: [GameCategory: Bool] = [:]
    private var chainPairExists: Bool {
        if let cached = Self.chainSupportCache[category] { return cached }
        let ok = places.contains { p in hopDistances(from: p).values.contains { $0 >= 3 } }
        Self.chainSupportCache[category] = ok
        return ok
    }

    /// Rastgele bir başlangıç–bitiş çifti ve aralarındaki en kısa rotalardan biri.
    func randomChainPair() -> (start: Place, end: Place, path: [Place])? {
        guard supportsChain else { return nil }
        let graph = neighbors
        let range = chainHops
        var fallback: (Place, Place, Int)?
        for start in places.filter({ !(graph[$0.id] ?? []).isEmpty }).shuffled() {
            let dist = hopDistances(from: start)
            let candidates = places.filter { range.contains(dist[$0.id] ?? -1) }
            if let end = candidates.randomElement(), let path = shortestPath(from: start, to: end) {
                return (start, end, path)
            }
            if let far = dist.max(by: { $0.value < $1.value }), far.value >= 3, far.value > fallback?.2 ?? 0,
               let end = place(id: far.key) {
                fallback = (start, end, far.value)
            }
        }
        if let (start, end, _) = fallback, let path = shortestPath(from: start, to: end) { return (start, end, path) }
        return nil
    }
}

// MARK: - Puanlar

extension Progression {
    /// Zamana karşı: bulunan her yer 25 XP × kategori zorluğu.
    static func timedPoints(score: Int, category: GameCategory) -> Int {
        Int((Double(score) * 25 * categoryFactor(category) / 5).rounded()) * 5
    }

    /// Zincir: en kısa rotayla 150, her fazla tahminde 25 eksik (en az 40) × kategori zorluğu; kaybedilen zincir 0.
    static func chainPoints(guesses: Int, optimal: Int, category: GameCategory) -> Int {
        let base = Double(max(40, 150 - 25 * max(0, guesses - optimal)))
        return Int((base * categoryFactor(category) / 5).rounded()) * 5
    }

    static func modesXP() -> Int {
        var total = 0
        for c in GameCategory.allCases {
            for run in TimedStats.load(c).runs { total += timedPoints(score: run.score, category: c) }
            for run in ChainStats.load(c).runs where run.won {
                total += chainPoints(guesses: run.guesses, optimal: run.optimal, category: c)
            }
        }
        return total
    }
}
