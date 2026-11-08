import SwiftUI

// Zamana karşı ve komşu zinciri modlarının panel parçaları. Web karşılıkları app.js'te
// (`renderTimed`, `renderChain`, `timedOverHTML`, `chainOverHTML`).

// MARK: - Zamana karşı

/// Kalan süre, bulunan sayısı ve pas düğmesi.
struct TimedBar: View {
    let game: GameModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = game.timedRemaining(at: context.date)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.format(remaining))
                        .font(Brand.heading(.largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(remaining <= 20 && game.timedStart != nil ? Color.red : Color.primary)
                    Text(L(game.timedStart == nil ? "timed.notStarted" : "timed.remaining"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(game.timedFound.count)")
                        .font(Brand.heading(.largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(ColorScale.found)
                    Text(L("timed.foundLabel"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) {
                // Süre çubuğu
                GeometryReader { geo in
                    Capsule()
                        .fill(remaining <= 20 ? Color.red : Brand.accent)
                        .frame(width: geo.size.width * remaining / GameModel.timedDuration, height: 3)
                }
                .frame(height: 3)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Süre başlamadan önce: kural ve "Başla" düğmesi.
struct TimedStartCard: View {
    let game: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("timed.title"), systemImage: "timer")
                .font(Brand.heading(.headline))
            Text(L("timed.intro.\(game.category.kind)"))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("timed.skipHint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { game.startTimer() } label: {
                Label(L("timed.start"), systemImage: "play.fill")
                    .frame(maxWidth: Platform.isMac ? nil : .infinity)
            }
            #if !os(tvOS)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            #endif
            .defaultActionShortcut()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Bu turda bulunan ve pas geçilen yerler.
struct TimedFoundList: View {
    let game: GameModel

    var body: some View {
        if !game.timedFound.isEmpty || !game.timedSkipped.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("timed.foundList"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                FlowLayout(spacing: 6) {
                    ForEach(game.timedFound) { chip($0, found: true) }
                    ForEach(game.timedSkipped) { chip($0, found: false) }
                }
            }
        }
    }

    private func chip(_ p: Place, found: Bool) -> some View {
        HStack(spacing: 4) {
            FlagView(place: p)
            Text(p.name)
            Image(systemName: found ? "checkmark" : "forward.fill").font(.caption2)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((found ? ColorScale.found : ColorScale.answerReveal).opacity(0.15), in: Capsule())
    }
}

// MARK: - Komşu zinciri

/// Başlangıç → bitiş ve kalan tahmin hakkı.
struct ChainCard: View {
    let game: GameModel

    var body: some View {
        if let start = game.chainStart, let end = game.chainEnd {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    endpoint(start)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    endpoint(end)
                }
                .font(Brand.heading(.title3))
                if !game.isOver {
                    Text(L("chain.intro.\(game.category.kind)", ["a": start.name, "b": end.name]))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(L("chain.left", ["n": game.chainGuessesLeft]))
                            .fontWeight(.semibold)
                            .foregroundStyle(game.chainGuessesLeft <= 2 ? Color.red : Color.primary)
                        Spacer()
                        Text(L("chain.optimal", ["n": game.chainOptimal]))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(ColorScale.chainEnd.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func endpoint(_ p: Place) -> some View {
        HStack(spacing: 5) {
            FlagView(place: p, height: 16)
            Text(p.name).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// Okyanusya gibi kara sınırı az olan kategoride zincir kurulamaz.
struct ChainUnavailableCard: View {
    let game: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("chain.title"), systemImage: "link").font(Brand.heading(.headline))
            Text(L("chain.unavailable")).font(.callout).fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 6) {
                ForEach(GameCategory.allCases.filter { PlaceSet.forCategory($0).supportsChain }) { c in
                    Button { game.switchCategory(c) } label: { Label(c.title, systemImage: c.symbol) }
                        .buttonStyle(.bordered)
                        #if !os(tvOS)
                        .controlSize(.small)
                        #endif
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Zincirde tahminler, girildiği sırayla; renk rotaya yakınlığı gösterir.
struct ChainGuessList: View {
    let game: GameModel

    var body: some View {
        if !game.guesses.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("chain.guesses"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(game.guesses) { g in
                            let cls = ChainClass(rawValue: g.distance) ?? .far
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(ColorScale.chain(cls))
                                    .frame(width: 18, height: 18)
                                FlagView(place: g.place)
                                Text(g.place.name)
                                Spacer()
                                Text(L("chain.class.\(cls.rawValue)")).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }
}

/// Bir rotanın yazısı: "Edirne → Kırklareli → … → Hakkari".
func routeText(_ path: [Place]) -> String { path.map(\.name).joined(separator: " → ") }

// MARK: - Oyun sonu

/// Zamana karşı bitince panelde: skor, rekor, düğmeler.
struct TimedOverBanner: View {
    let game: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("timed.over"), systemImage: "timer").font(.headline).foregroundStyle(Brand.accent)
            Text(L("timed.result.\(game.category.kind)", ["n": game.timedFound.count]))
                .font(Brand.heading(.title))
            if let r = game.timedResult {
                Text(r.isRecord ? L("timed.record") : L("timed.best", ["n": r.best]))
                    .font(.callout.weight(r.isRecord ? .bold : .regular))
                    .foregroundStyle(r.isRecord ? ColorScale.found : .secondary)
            }
            Text(L("timed.lastHidden", ["name": game.answer.name]))
                .font(.callout)
                .foregroundStyle(.secondary)
            OverButtons(game: game)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Zincir bitince panelde: kurulan ya da en kısa rota.
struct ChainOverBanner: View {
    let game: GameModel

    var body: some View {
        let won = game.status == .won
        VStack(alignment: .leading, spacing: 8) {
            Label(L(won ? "chain.won" : "chain.lost"), systemImage: won ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.headline)
                .foregroundStyle(won ? ColorScale.found : ColorScale.answerReveal)
            if won {
                Text(L(game.guesses.count == game.chainOptimal ? "chain.perfect" : "chain.foundIn",
                       ["n": game.guesses.count, "m": game.chainOptimal]))
                    .font(.callout)
            }
            Text(L(won ? "chain.yourRoute" : "chain.shortest"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(routeText(won ? (game.chainPath ?? []) : game.chainShortest))
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            OverButtons(game: game)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// "Sonuç" ve "Yeni oyun" (aynı modda yeni tur).
struct OverButtons: View {
    let game: GameModel

    var body: some View {
        HStack {
            Button(L("result")) { game.showResult = true }
            Button(L("newGame")) { game.newRound() }
                .defaultActionShortcut()
        }
    }
}

// MARK: - Akış düzeni

/// Öğeleri satıra sığdığı kadar yan yana dizer, sığmayanı alt satıra geçirir.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
