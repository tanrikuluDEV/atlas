import SwiftUI

/// Kategori seçici: her kategori bir kart (küçük harita, yer sayısı, bugünkü günlük bulmacanın durumu).
/// Mac'te araç çubuğundan açılan bir balon, iPhone'da bir sayfa. Web karşılığı: `openCategoryPicker` (app.js).
struct CategoryPicker: View {
    let game: GameModel
    @Binding var isPresented: Bool

    private let today = DailyPuzzle.dayIndex(for: .now)

    /// Satır satır ızgara (tembel ızgara değil; böylece ekran dışı görüntüde de çizilir).
    private var grid: some View {
        let all = Array(GameCategory.allCases.enumerated())
        let perRow = Platform.isMac ? 4 : 2
        return VStack(spacing: 10) {
            ForEach(Array(stride(from: 0, to: all.count, by: perRow)), id: \.self) { start in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(all[start..<min(start + perRow, all.count)], id: \.element) { i, c in
                        Button {
                            isPresented = false
                            game.switchCategory(c)
                        } label: {
                            CategoryCard(category: c, selected: c == game.category,
                                         saved: GameModel.savedDaily(category: c, day: today))
                        }
                        .buttonStyle(.plain)
                        #if os(macOS)
                        .help("⌘\(i + 1)")
                        #endif
                    }
                }
                .fixedSize(horizontal: false, vertical: true) // satırdaki kartlar eşit boyda
            }
        }
        .padding(3) // seçili kartın halkası kırpılmasın
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("category")).font(Brand.heading(.title))
                    Text(L("picker.subtitle")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .cancelActionShortcut()
                .accessibilityLabel(L("close"))
            }
            #if os(macOS)
            grid // 8 kart balona sığar
            #else
            ScrollView { grid }
            #endif
        }
        .padding(Platform.isMac ? 20 : 16)
        #if os(macOS)
        .frame(width: 680)
        #else
        .presentationDetents([.large])
        #endif
        .background(Brand.panel)
    }
}

private struct CategoryCard: View {
    let category: GameCategory
    let selected: Bool
    let saved: (status: GameStatus, guesses: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CategoryThumb(category: category)
                .frame(height: Platform.isMac ? 92 : 80)
            VStack(alignment: .leading, spacing: 2) {
                Label(category.title, systemImage: category.symbol)
                    .font(Brand.heading(.headline))
                    .lineLimit(2)
                Text(L("count.\(category.kind)", ["n": PlaceSet.forCategory(category).places.count]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                badge.padding(.top, 6)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("Card"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(selected ? Brand.accent : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
        .shadow(color: selected ? Brand.accent.opacity(0.25) : .clear, radius: 4)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private var badge: some View {
        let (text, color): (String, Color) = switch saved {
        case let s? where s.status == .won: ("✓ " + L("picker.won", ["n": s.guesses]), ColorScale.found)
        case let s? where s.status == .lost: (L("picker.lost"), ColorScale.answerReveal)
        case let s? where s.guesses > 0: ("\(L("picker.playing")) · \(s.guesses)", .secondary)
        default: (L("picker.new"), Brand.accent)
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Kategorinin küçük haritası: yerleri marka turuncusuyla, çevresi soluk (web: drawCategoryThumb).
private struct CategoryThumb: View {
    let category: GameCategory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { ctx, size in
            let dark = colorScheme == .dark
            let sea = dark ? Color(red: 0.075, green: 0.118, blue: 0.173) : Color(red: 0.933, green: 0.949, blue: 0.957)
            let land = dark ? Color(red: 0.145, green: 0.196, blue: 0.267) : Color(red: 0.902, green: 0.882, blue: 0.847)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(sea))
            let geo = PlaceSet.forCategory(category).geometry
            let b = geo.bounds
            let s = min((size.width - 12) / b.width, (size.height - 12) / b.height)
            let t = CGAffineTransform(translationX: size.width / 2 - b.midX * s, y: size.height / 2 - b.midY * s)
                .scaledBy(x: s, y: s)
            for path in geo.backgroundPaths { ctx.fill(path.applying(t), with: .color(land)) }
            for path in geo.paths {
                let shape = path.applying(t)
                ctx.fill(shape, with: .color(Brand.orange))
                ctx.stroke(shape, with: .color(sea), lineWidth: 0.6)
            }
        }
        .accessibilityHidden(true)
    }
}
