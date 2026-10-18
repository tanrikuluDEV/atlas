import Charts
import SwiftUI

/// Oyun geçmişinden tahmin sayısının zaman içindeki değişimini gösterir.
struct ProgressSection: View {
    let stats: Stats
    let places: PlaceSet

    private static let window = 5

    private struct Point: Identifiable {
        let number: Int
        let record: GameRecord
        /// Son `window` kazanılan oyunun ortalaması (bu oyun dahil).
        let average: Double?
        var id: Int { number }
    }

    private var points: [Point] {
        var wins: [Int] = []
        return stats.history.enumerated().map { i, r in
            if r.won { wins.append(r.guesses) }
            let recent = wins.suffix(Self.window)
            let avg = recent.isEmpty ? nil : Double(recent.reduce(0, +)) / Double(recent.count)
            return Point(number: i + 1, record: r, average: avg)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("prog.title")).font(.headline)

            if stats.history.count < 2 {
                Text(L("prog.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                trendSummary
                chart
                recentGames
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Özet

    @ViewBuilder
    private var trendSummary: some View {
        let recent = stats.recentAverage(last: 10)
        let overall = stats.history.filter(\.won).isEmpty
            ? nil
            : Double(stats.history.filter(\.won).map(\.guesses).reduce(0, +)) / Double(stats.history.filter(\.won).count)

        HStack(spacing: 24) {
            metric(L("prog.last10"), recent)
            metric(L("prog.all"), overall)
            if let recent, let overall {
                let diff = recent - overall
                // Daha az tahmin daha iyi: ortalamanın altına inmek gelişme demek.
                let improving = diff < -0.05
                let worsening = diff > 0.05
                Label(L(improving ? "prog.improving" : worsening ? "prog.worsening" : "prog.steady"),
                      systemImage: improving ? "arrow.down.right" : worsening ? "arrow.up.right" : "arrow.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(improving ? ColorScale.found : worsening ? Color.orange : Color.secondary)
            }
        }
    }

    private func metric(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { $0.formatted(.number.precision(.fractionLength(1)).locale(L10n.shared.language.locale)) } ?? "–")
                .font(.title3.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Grafik

    private var chart: some View {
        let data = points
        return Chart {
            ForEach(data) { p in
                PointMark(x: .value(L("prog.axisGame"), p.number), y: .value(L("prog.axisGuesses"), p.record.guesses))
                    .foregroundStyle(p.record.won ? ColorScale.found : Color.gray)
                    .symbol(p.record.won ? .circle : .cross)
                    .symbolSize(p.record.won ? 36 : 44)
            }
            ForEach(data.filter { $0.average != nil }) { p in
                LineMark(x: .value(L("prog.axisGame"), p.number), y: .value(L("prog.average"), p.average!))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXAxisLabel(L("prog.axisGame"))
        .chartYAxisLabel(L("prog.axisGuesses"))
        .chartXScale(domain: 1...max(data.count, 2))
        .chartLegend(.hidden)
        .frame(height: 170)
        .overlay(alignment: .topTrailing) { legend }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(Circle().fill(ColorScale.found).frame(width: 7, height: 7), L("prog.won"))
            legendItem(Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.gray), L("prog.gaveUp"))
            legendItem(Capsule().fill(Color.accentColor).frame(width: 14, height: 3), L("prog.window", ["n": Self.window]))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
    }

    private func legendItem(_ symbol: some View, _ label: String) -> some View {
        HStack(spacing: 4) { symbol; Text(label) }
    }

    // MARK: - Son oyunlar

    private var recentGames: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("prog.recent"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(stats.history.suffix(5).reversed()) { r in
                HStack {
                    Image(systemName: r.won ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(r.won ? ColorScale.found : .secondary)
                    Text(places.place(id: r.answerID)?.name ?? "?")
                    Spacer()
                    Text(r.won ? L("guesses", ["n": r.guesses]) : L("prog.recentLost", ["guesses": L("guesses", ["n": r.guesses])]))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(r.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(L10n.shared.language.locale)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 96, alignment: .trailing)
                }
                .font(.callout)
            }
        }
    }
}
