import SwiftUI

// Paneldeki ek parçalar: sıcaklık göstergesi, boş tur kartı, günlük geri sayım ve diğer günlükler, rozetler.
// Web karşılıkları app.js'te: heatHTML, emptyHTML, countdownHTML, badgeHTML.

/// Tahminin yakınlığı 0…1 (1 = komşu); renk skalasıyla aynı karekök ölçeği.
func proximity(of guess: Guess, max maxKm: Int) -> Double {
    1 - min(1, max(0, sqrt(Double(guess.distance) / Double(max(maxKm, 1)))))
}

// MARK: - Sıcaklık göstergesi

/// Son tahminin ne kadar yakın olduğu: buzdan ateşe bir çubuk. Öncekinden yakınsa hafifçe titrer.
struct HeatGauge: View {
    let game: GameModel
    @State private var shakes: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func level(_ p: Double) -> Int {
        p >= 1 ? 5 : p > 0.8 ? 4 : p > 0.6 ? 3 : p > 0.35 ? 2 : 1
    }

    var body: some View {
        if let last = game.lastGuess, !game.isOver {
            let max = game.places.maxDistance
            let p = proximity(of: last, max: max)
            let best = game.closest.map { proximity(of: $0, max: max) } ?? p
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(L("heat.\(Self.level(p))"))
                        .font(Brand.heading(.headline))
                    Spacer()
                    if game.lastImproved && game.guesses.count > 1 {
                        Text(L("heat.closer"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.accent)
                            .transition(.opacity)
                    }
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: Self.gradient(max: max), startPoint: .leading, endPoint: .trailing))
                        // En yakın tahmin: ince bir çizgi.
                        Capsule().fill(Color.primary.opacity(0.55))
                            .frame(width: 2, height: 14)
                            .offset(x: best * (w - 2))
                        Circle()
                            .fill(ColorScale.color(forDistance: last.distance, max: max))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .frame(width: 16, height: 16)
                            .offset(x: p * (w - 16))
                    }
                    .frame(height: 16)
                }
                .frame(height: 16)
            }
            .modifier(Shake(amount: shakes))
            .animation(.spring(duration: 0.5), value: last)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(L("heat.label")): \(L("heat.\(Self.level(p))"))")
            .onChange(of: game.lastGuess) {
                guard game.lastImproved, game.guesses.count > 1, !reduceMotion else { return }
                withAnimation(.linear(duration: 0.45)) { shakes += 1 }
            }
        }
    }

    /// Soldan sağa: buz mavisi, soluk krem (uzak) … koyu kırmızı (komşu).
    static func gradient(max: Int) -> [Color] {
        [Color(red: 0.62, green: 0.80, blue: 0.95)]
            + stride(from: 1.0, through: 0, by: -0.2).map { f in ColorScale.color(forDistance: Int(Double(max) * f * f), max: max) }
    }
}

/// Yatay titreme; `amount` her arttığında bir kez sallanır.
struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 3 * sin(amount * .pi * 6), y: 0))
    }
}

// MARK: - Boş tur

/// Henüz tahmin yokken: kategorinin silüeti, kaç yer arasından seçildiği ve bir oyun taktiği.
struct EmptyRoundCard: View {
    let game: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CategoryThumb(category: game.category)
                .frame(height: Platform.isTV ? 160 : Platform.isMac ? 120 : 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(L("empty.pool.\(game.category.kind)", ["n": game.places.places.count]))
                .font(Brand.heading(.headline))
            Text(L("empty.start"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lightbulb.fill").foregroundStyle(Brand.accent)
                // Her turda sıradaki taktik.
                Text(L("tip.\(game.roundID % 4 + 1)"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Günlük geri sayım

/// "Yeni bulmacaya 05:12:33" (yerel gece yarısına kadar, her saniye güncellenir).
struct DailyCountdown: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label(L("countdown", ["time": Self.format(GameModel.timeUntilNextPuzzle(from: context.date))]),
                  systemImage: "clock")
                .monospacedDigit()
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}

/// Bugünün bitmemiş diğer günlük bulmacalarına kısayollar.
struct OtherDailies: View {
    let game: GameModel

    var body: some View {
        let others = GameModel.unfinishedDailies(day: game.dayIndex).filter { $0 != game.category }
        if others.isEmpty {
            Text(L("countdown.allDone")).font(.callout)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("countdown.others"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(others) { c in
                            Button { game.switchCategory(c) } label: {
                                Label(c.title, systemImage: c.symbol)
                            }
                            .buttonStyle(.bordered)
                            #if !os(tvOS)
                            .controlSize(.small)
                            #endif
                        }
                    }
                    .padding(Platform.isTV ? 12 : 0) // TV'de odak büyümesi kırpılmasın
                }
            }
        }
    }
}

// MARK: - Rozetler

struct BadgeView: View {
    let badge: Badge
    var size: CGFloat = 46

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(badge.earned ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.primary.opacity(0.07)))
                if !badge.earned && badge.current > 0 {
                    Circle()
                        .trim(from: 0, to: CGFloat(badge.current) / CGFloat(badge.target))
                        .stroke(Brand.accent.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.5)
                }
                Image(systemName: badge.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(badge.earned ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
            }
            .frame(width: size, height: size)
            Text(badge.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badge.earned ? .primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(badge.earned || badge.target == 1 ? badge.detail : "\(badge.current)/\(badge.target)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .monospacedDigit()
        }
        .frame(width: 96)
        .help(badge.detail)
        .accessibilityElement(children: .combine)
    }
}

/// İstatistik penceresindeki rozet rafı (tüm kategoriler birlikte).
struct BadgeShelf: View {
    var body: some View {
        let badges = Badges.all()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("badges.title")).font(Brand.heading(.headline))
                Text(L("badges.count", ["n": badges.filter(\.earned).count, "total": badges.count]))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .top)], spacing: 14) {
                ForEach(badges) { BadgeView(badge: $0) }
            }
        }
    }
}
