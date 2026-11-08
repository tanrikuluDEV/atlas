import Foundation

/// Rozet: bir hedef ve ona ne kadar yaklaşıldığı. Web karşılığı `web/js/badges.js` (aynı rozetler, aynı koşullar).
struct Badge: Identifiable, Hashable {
    let id: String
    /// SF Symbol adı.
    let symbol: String
    let name: String
    let detail: String
    let current: Int
    let target: Int

    var earned: Bool { current >= target }
}

/// Rozetler ayrıca saklanmaz; tüm kategorilerin istatistiklerinden hesaplanır (puan gibi).
enum Badges {
    static func all() -> [Badge] {
        var wins = 0
        var best = Int.max
        var maxStreak = 0
        var categoriesWon = 0
        var expertWins = 0
        var explorers: [Badge] = []

        for c in GameCategory.allCases {
            let daily = Stats.load(key: Stats.key(category: c, mode: .daily))
            let practice = Stats.load(key: Stats.key(category: c, mode: .practice))
            let won = daily.won + practice.won
            wins += won
            if won > 0 { categoriesWon += 1 }
            if let m = (daily.winningGuessCounts + practice.winningGuessCounts).min() { best = min(best, m) }
            maxStreak = max(maxStreak, daily.maxStreak)
            expertWins += (daily.history + practice.history).filter { $0.won && $0.expert == true }.count

            let places = PlaceSet.forCategory(c)
            let found = Set((daily.history + practice.history).filter(\.won).map(\.answerID))
                .filter { places.place(id: $0) != nil }
            explorers.append(Badge(id: "explorer.\(c.rawValue)", symbol: "map.fill",
                                   name: L("badge.explorer.name", ["cat": c.title]),
                                   detail: L("badge.explorer.desc.\(c.kind)", ["n": places.places.count]),
                                   current: found.count, target: places.places.count))
        }

        func badge(_ id: String, _ symbol: String, _ current: Int, _ target: Int) -> Badge {
            Badge(id: id, symbol: symbol, name: L("badge.\(id).name"), detail: L("badge.\(id).desc"),
                  current: min(current, target), target: target)
        }
        return [
            badge("firstWin", "flag.checkered", wins, 1),
            badge("sharp", "eye.fill", best <= 3 ? 1 : 0, 1),
            badge("ace", "scope", best == 1 ? 1 : 0, 1),
            badge("streak3", "flame", maxStreak, 3),
            badge("streak7", "flame.fill", maxStreak, 7),
            badge("streak30", "sun.max.fill", maxStreak, 30),
            badge("wins10", "figure.walk", wins, 10),
            badge("wins50", "airplane", wins, 50),
            badge("wins100", "crown.fill", wins, 100),
            badge("allCategories", "globe.europe.africa.fill", categoriesWon, GameCategory.allCases.count),
            badge("expert", "eye.slash.fill", expertWins, 1),
            badge("expert10", "graduationcap.fill", expertWins, 10),
        ] + explorers
    }

    static func earnedIDs() -> Set<String> {
        Set(all().filter(\.earned).map(\.id))
    }
}
