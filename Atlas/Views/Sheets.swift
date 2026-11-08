import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ResultView: View {
    let game: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            switch game.mode {
            case .timed: timedHeader
            case .chain: chainHeader
            default: classicHeader
            }

            if let reward = game.reward {
                LevelCard(progress: reward.after, reward: reward)
            }
            if !game.newBadges.isEmpty {
                VStack(spacing: 8) {
                    Text(L("badges.new")).font(Brand.heading(.headline)).foregroundStyle(Brand.accent)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(game.newBadges.prefix(4)) { BadgeView(badge: $0) }
                    }
                }
            }
            if game.mode.isClassic { StatsSummary(stats: game.currentStats) }
            if game.mode == .daily {
                DailyCountdown()
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            let layout = Platform.isMac ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout(spacing: 10))
            layout {
                // Enter doğrudan yeni oyuna geçer.
                Button(L("newGame")) { dismiss(); game.newRound() }
                    .defaultActionShortcut()
                shareButton
                // Sayfa kapanınca haritada tahminler sırayla yeniden oynatılır.
                if game.mode.isClassic {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { game.startReplay() }
                    } label: {
                        Label(L("replay.button"), systemImage: "play.circle")
                    }
                }
                Button(L("close")) { dismiss() }
                    .cancelActionShortcut()
            }
            #if os(iOS)
            .buttonStyle(.bordered)
            .controlSize(.large)
            #endif
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .sheetWidth(420)
        #if os(iOS)
        // Seviye kartı varken içerik yarım sayfaya sığmaz.
        .presentationDetents(game.reward == nil ? [.medium, .large] : [.large])
        #endif
    }

    @ViewBuilder
    private var timedHeader: some View {
        Image(systemName: "timer")
            .font(.system(size: 40))
            .foregroundStyle(Brand.accent)
        Text(L("timed.over")).font(Brand.heading(.largeTitle))
        Text(L("timed.result.\(game.category.kind)", ["n": game.timedFound.count])).font(Brand.heading(.title2))
        if let r = game.timedResult {
            Text(r.isRecord ? L("timed.record") : L("timed.best", ["n": r.best]))
                .fontWeight(r.isRecord ? .bold : .regular)
                .foregroundStyle(r.isRecord ? ColorScale.found : .secondary)
        }
    }

    @ViewBuilder
    private var chainHeader: some View {
        let won = game.status == .won
        Image(systemName: won ? "link" : "map.fill")
            .font(.system(size: 40))
            .foregroundStyle(won ? ColorScale.found : ColorScale.answerReveal)
        Text(L(won ? "chain.won" : "chain.lost")).font(Brand.heading(.largeTitle))
        if won {
            Text(L(game.guesses.count == game.chainOptimal ? "chain.perfect" : "chain.foundIn",
                   ["n": game.guesses.count, "m": game.chainOptimal]))
        }
        VStack(spacing: 4) {
            Text(L(won ? "chain.yourRoute" : "chain.shortest"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(routeText(won ? (game.chainPath ?? []) : game.chainShortest)).fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private var classicHeader: some View {
            Image(systemName: game.status == .won ? "party.popper.fill" : "map.fill")
                .font(.system(size: 40))
                .foregroundStyle(game.status == .won ? ColorScale.found : ColorScale.answerReveal)

            if game.status == .won {
                Text(L("congrats")).font(Brand.heading(.largeTitle))
                Text(LocalizedStringKey(L("result.won.\(game.category.kind)", ["name": "**\(game.answer.flaggedName)**"])
                                        + "\n" + L("result.foundIn", ["n": game.guesses.count])))
            } else {
                Text(L("nextTime")).font(Brand.heading(.largeTitle))
                Text(LocalizedStringKey(L("result.lost.\(game.category.kind)", ["name": "**\(game.answer.flaggedName)**"])))
            }
    }

    @ViewBuilder
    private var shareButton: some View {
        #if os(macOS)
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(game.shareText, forType: .string)
            copied = true
        } label: {
            Label(L(copied ? "copied" : "copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        #elseif os(iOS)
        ShareLink(item: game.shareText) {
            Label(L("share"), systemImage: "square.and.arrow.up")
        }
        #endif
    }
}

struct StatsView: View {
    let game: GameModel
    @State private var tab: GameMode
    @State private var category: GameCategory
    @Environment(\.dismiss) private var dismiss

    init(game: GameModel) {
        self.game = game
        _tab = State(initialValue: game.mode.isClassic ? game.mode : .practice)
        _category = State(initialValue: game.category)
    }

    private var stats: Stats {
        if category == game.category { return tab == .daily ? game.dailyStats : game.practiceStats }
        var s = Stats.load(key: Stats.key(category: category, mode: tab))
        if tab == .daily { s.refreshStreak(today: DailyPuzzle.dayIndex(for: .now)) }
        return s
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(L("stats")).font(Brand.heading(.title))
            HStack(spacing: 12) {
                Picker(L("category"), selection: $category) {
                    ForEach(GameCategory.allCases) { c in
                        Label(c.title, systemImage: c.symbol).tag(c)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                Picker(L("mode"), selection: $tab) {
                    ForEach(GameMode.classic) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }

            // Geçmiş uzadıkça içerik pencereden taşmasın diye kaydırılabilir.
            ScrollView {
                details.padding(.horizontal, 28)
            }
            .frame(maxHeight: Platform.isMac ? 520 : .infinity)

            Button(L("close")) { dismiss() }.defaultActionShortcut()
        }
        .padding(.vertical, 24)
        .sheetWidth(560)
    }

    private var details: some View {
        VStack(spacing: 18) {
            LevelCard(progress: LevelProgress(xp: Progression.totalXP()))
            BadgeShelf()
            Divider()
            StatsSummary(stats: stats, streakLabel: L(tab == .daily ? "stats.streakDays" : "stats.streak"))

            VStack(alignment: .leading, spacing: 6) {
                Text(L("stats.distribution")).font(Brand.heading(.headline))
                let dist = stats.distribution
                let maxCount = max(dist.map(\.count).max() ?? 0, 1)
                ForEach(dist, id: \.label) { row in
                    HStack {
                        Text(row.label).frame(width: 48, alignment: .leading).monospacedDigit()
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Brand.accent.opacity(row.count == 0 ? 0.2 : 0.8))
                                .frame(width: max(8, geo.size.width * CGFloat(row.count) / CGFloat(maxCount)))
                        }
                        .frame(height: 16)
                        Text("\(row.count)").frame(width: 28, alignment: .trailing).monospacedDigit()
                    }
                }
            }

            if let avg = stats.averageGuesses {
                Text(L("stats.average", ["v": avg.formatted(.number.precision(.fractionLength(1)).locale(L10n.shared.language.locale))]))
                    .foregroundStyle(.secondary)
            }
            ModesSummary(category: category)
            Divider()
            CalendarSection(stats: stats, mode: tab)
            Divider()
            DiscoverySection(category: category)
            Divider()
            ProgressSection(stats: stats, places: PlaceSet.forCategory(category))

            Text(L("stats.footer.\(tab.rawValue)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Kategorinin zamana karşı rekoru ve zincir sonuçları.
private struct ModesSummary: View {
    let category: GameCategory

    var body: some View {
        let timed = TimedStats.load(category)
        let chain = ChainStats.load(category)
        if !timed.runs.isEmpty || !chain.runs.isEmpty {
            Divider()
            HStack(spacing: 20) {
                if !timed.runs.isEmpty {
                    item("\(timed.best)", L("stats.timedBest"), "timer")
                    item("\(timed.runs.count)", L("stats.timedRuns"), "timer")
                }
                if !chain.runs.isEmpty {
                    item("\(chain.won)/\(chain.played)", L("stats.chainWon"), "link")
                    item("\(chain.perfect)", L("stats.chainPerfect"), "link")
                }
            }
        }
    }

    private func item(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Brand.heading(.title2)).monospacedDigit()
            Label(label, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 64)
    }
}

private struct StatsSummary: View {
    let stats: Stats
    var streakLabel = L("stats.streak")

    var body: some View {
        HStack(spacing: 20) {
            item("\(stats.played)", L("stats.played"))
            item((Double(stats.winRate) / 100).formatted(.percent.locale(L10n.shared.language.locale)), L("stats.winRate"))
            item("\(stats.currentStreak)", streakLabel)
            item("\(stats.maxStreak)", L("stats.maxStreak"))
        }
    }

    private func item(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Brand.heading(.title2)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 64)
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("help")).font(Brand.heading(.title))

            Text(L("help.intro"))

            VStack(alignment: .leading, spacing: 8) {
                bullet(L(Platform.isTV ? "help.b1TV" : "help.b1"))
                bullet(L("help.b2"))
                bullet(L("help.b3"))
                bullet(L("help.b4"))
                bullet(L("help.modes"))
                bullet(L("help.hints"))
                bullet(L("help.xp"))
                bullet(L(Platform.isMac ? "help.kmMac" : "help.kmPhone"))
            }

            HStack(spacing: 0) {
                ForEach([0, 3, 15, 40, 100, 250, 1_000], id: \.self) { t in
                    ColorScale.color(forDistance: t, max: 1_000)
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                Text(L("help.near"))
                Spacer()
                Text(L("help.far"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(LocalizedStringKey(L(Platform.isTV ? "help.practiceTV" : "help.practice")))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L("help.start")) { dismiss() }.defaultActionShortcut()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(28)
        .sheetWidth(440)
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
