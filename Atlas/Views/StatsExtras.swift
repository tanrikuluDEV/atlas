import SwiftUI

// MARK: - Takvim

/// Son 18 haftanın takvimi: günlükte kaç tahminde bulduğun, alıştırmada kaç oyun oynadığın.
struct CalendarSection: View {
    let stats: Stats
    let mode: GameMode

    private static let weeks = 18
    private static let cell: CGFloat = 12
    private static let gap: CGFloat = 3

    private struct Day: Identifiable {
        let date: Date
        let level: Int      // 0 = oynanmadı, 1...4 = yoğunluk
        let lost: Bool
        let tip: String
        let isToday: Bool
        let isFuture: Bool
        var id: Date { date }
    }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Pazartesi
        return c
    }

    /// Haftalar (sütunlar), her biri Pazartesi'den Pazar'a 7 gün.
    private var columns: [[Day]] {
        let today = cal.startOfDay(for: .now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7 // Pzt = 0
        let firstMonday = cal.date(byAdding: .day, value: -weekday - (Self.weeks - 1) * 7, to: today)!
        let byDay = Dictionary(grouping: stats.history) { cal.startOfDay(for: $0.date) }
        let fmt = Date.FormatStyle().day().month(.wide).locale(L10n.shared.language.locale)

        return (0..<Self.weeks).map { w in
            (0..<7).map { d in
                let date = cal.date(byAdding: .day, value: w * 7 + d, to: firstMonday)!
                let recs = byDay[date] ?? []
                var level = 0, lost = false
                let day = date.formatted(fmt)
                var tip = L("cal.notPlayed", ["date": day])
                if let r = recs.first {
                    if mode == .daily {
                        if r.won {
                            level = r.guesses <= 3 ? 4 : r.guesses <= 6 ? 3 : r.guesses <= 10 ? 2 : 1
                            tip = L("cal.foundIn", ["date": day, "n": r.guesses])
                        } else {
                            lost = true
                            tip = L("cal.gaveUp", ["date": day])
                        }
                    } else {
                        let n = recs.count
                        level = n >= 5 ? 4 : n >= 3 ? 3 : n == 2 ? 2 : 1
                        tip = L("cal.games", ["date": day, "n": n])
                    }
                }
                return Day(date: date, level: level, lost: lost, tip: tip, isToday: date == today, isFuture: date > today)
            }
        }
    }

    static func color(level: Int, lost: Bool) -> Color {
        if lost { return Color(red: 0.79, green: 0.64, blue: 0.64) }
        switch level {
        case 1: return Color(red: 0.72, green: 0.89, blue: 0.75)
        case 2: return Color(red: 0.45, green: 0.77, blue: 0.53)
        case 3: return Color(red: 0.24, green: 0.62, blue: 0.35)
        case 4: return Color(red: 0.12, green: 0.44, blue: 0.22)
        default: return Color.primary.opacity(0.08)
        }
    }

    var body: some View {
        let cols = columns
        let played = cols.joined().filter { $0.level > 0 || $0.lost }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L("cal.title")).font(.headline)
                Text(L("cal.summary", ["w": Self.weeks, "n": played])).font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: Self.gap) {
                // Gün adları
                VStack(alignment: .leading, spacing: Self.gap) {
                    Text(" ").font(.system(size: 9)).frame(height: 12)
                    ForEach(0..<7, id: \.self) { d in
                        Text(d % 2 == 0 && d < 6 ? weekdayName(d) : "")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                            .frame(width: 22, height: Self.cell, alignment: .leading)
                    }
                }
                ForEach(Array(cols.enumerated()), id: \.offset) { w, days in
                    VStack(spacing: Self.gap) {
                        // Ay adı, ayın ilk Pazartesi'sinin sütununda
                        let month = cal.component(.month, from: days[0].date)
                        let showMonth = w == 0 || cal.component(.month, from: cols[w - 1][0].date) != month
                        Text(showMonth ? monthName(days[0].date) : " ")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                            .fixedSize()
                            .frame(width: Self.cell, height: 12, alignment: .leading)
                        ForEach(days) { day in
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(day.isFuture ? Color.clear : Self.color(level: day.level, lost: day.lost))
                                .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(day.isToday ? Color.primary : .clear, lineWidth: 1.2))
                                .frame(width: Self.cell, height: Self.cell)
                                .help(day.tip)
                        }
                    }
                }
            }
            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            if mode == .daily {
                Text(L("cal.fewGuesses"))
                ForEach([4, 3, 2, 1], id: \.self) { swatch(level: $0) }
                Text(L("cal.many"))
                swatch(level: 0, lost: true).padding(.leading, 6)
                Text(L("cal.gaveUpShort"))
            } else {
                Text(L("cal.few"))
                ForEach([1, 2, 3, 4], id: \.self) { swatch(level: $0) }
                Text(L("cal.manyGames"))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).locale(L10n.shared.language.locale)).replacingOccurrences(of: ".", with: "")
    }

    /// Pazartesiden itibaren d. günün kısa adı (5 Ocak 2026 bir Pazartesi).
    private func weekdayName(_ d: Int) -> String {
        let date = cal.date(from: DateComponents(year: 2026, month: 1, day: 5 + d))!
        return date.formatted(.dateTime.weekday(.abbreviated).locale(L10n.shared.language.locale)).replacingOccurrences(of: ".", with: "")
    }

    private func swatch(level: Int, lost: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Self.color(level: level, lost: lost)).frame(width: 10, height: 10)
    }
}

// MARK: - Keşfettiklerim

/// Kategoride bulunan yerler (günlük ve alıştırmada kazanılan oyunlar) ve bunları gösteren küçük harita.
struct DiscoverySection: View {
    let category: GameCategory

    @Environment(\.colorScheme) private var colorScheme

    private var places: PlaceSet { PlaceSet.forCategory(category) }

    private var found: Set<Int> {
        let ids = [GameMode.daily, .practice].flatMap { mode in
            Stats.load(key: Stats.key(category: category, mode: mode)).history.filter(\.won).map(\.answerID)
        }
        return Set(ids.filter { places.place(id: $0) != nil })
    }

    var body: some View {
        let found = found
        let total = places.places.count
        let pct = total == 0 ? 0 : Int((Double(found.count) / Double(total) * 100).rounded())
        VStack(alignment: .leading, spacing: 8) {
            Text(L("disc.title")).font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(found.count)").font(.title3.bold())
                Text(L("disc.found.\(category.kind)", ["total": total]))
                Text("(\((Double(pct) / 100).formatted(.percent.locale(L10n.shared.language.locale))))").foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                Capsule().fill(Color.primary.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule().fill(ColorScale.found).frame(width: geo.size.width * CGFloat(pct) / 100)
                    }
            }
            .frame(height: 6)
            map(found: found)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(L("disc.hint.\(category.kind)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func map(found: Set<Int>) -> some View {
        let dark = colorScheme == .dark
        let geometry = places.geometry
        return Canvas { ctx, size in
            let b = geometry.bounds
            let s = min((size.width - 8) / b.width, (size.height - 8) / b.height)
            let t = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: size.width / 2 - b.midX * s, ty: size.height / 2 - b.midY * s)
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(dark ? Color(red: 0.07, green: 0.09, blue: 0.13) : Color(red: 0.89, green: 0.93, blue: 0.97)))
            for path in geometry.backgroundPaths {
                ctx.fill(path.applying(t), with: .color(dark ? Color(white: 0.17) : Color(white: 0.95)))
            }
            let border = dark ? Color.black.opacity(0.6) : Color.white
            for (i, path) in geometry.paths.enumerated() {
                let shape = path.applying(t)
                let isFound = found.contains(places.places[i].id)
                ctx.fill(shape, with: .color(isFound ? ColorScale.found : (dark ? Color(white: 0.30) : Color(white: 0.82))))
                ctx.stroke(shape, with: .color(border), lineWidth: 0.4)
                let r = shape.boundingRect
                if isFound && r.width < 4 && r.height < 4 {
                    ctx.fill(Path(ellipseIn: CGRect(x: r.midX - 3, y: r.midY - 3, width: 6, height: 6)), with: .color(ColorScale.found))
                }
            }
        }
    }
}
