#if os(tvOS)
import SwiftUI

/// Apple TV'de sağ sütunun başı: başlık, kategori, mod, dil ve diğer eylemler (kumandayla odaklanılır).
/// Harita ekranın sol yarısını köşeden köşeye kapladığı için başlık dar sütuna iki satır hâlinde sığar.
struct TVHeader: View {
    let game: GameModel
    @Binding var showStats: Bool
    @Binding var showHelp: Bool
    @Binding var showSettings: Bool
    @State private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.mode == .daily ? "Atlas #\(game.puzzleNumber)" : "Atlas · \(L("mode.practice"))")
                        .font(.headline)
                        .lineLimit(1)
                        .fixedSize()
                    Text(game.category.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Menu {
                    Picker(L("language"), selection: $l10n.language) {
                        ForEach(AppLanguage.allCases) { Text("\($0.flag) \($0.nativeName)").tag($0) }
                    }
                } label: {
                    Text(l10n.language.flag).font(.system(size: 24)).fixedSize().accessibilityLabel(L("language"))
                }
                .fixedSize()
                Menu {
                    if game.mode == .practice {
                        Button { game.newPractice() } label: { Label(L("newGame"), systemImage: "arrow.clockwise") }
                    }
                    Button { showStats = true } label: { Label(L("stats"), systemImage: "chart.bar.fill") }
                    Button { showSettings = true } label: { Label(L("settings"), systemImage: "gearshape") }
                    Button { showHelp = true } label: { Label(L("help"), systemImage: "questionmark.circle") }
                } label: {
                    Image(systemName: "ellipsis").accessibilityLabel(L("menu"))
                }
                .fixedSize()
            }
            HStack(spacing: 16) {
                Menu {
                    Picker(L("category"), selection: Binding(get: { game.category }, set: { game.switchCategory($0) })) {
                        ForEach(GameCategory.allCases) { c in
                            Label(c.title, systemImage: c.symbol).tag(c)
                        }
                    }
                } label: {
                    Label(game.category.title, systemImage: game.category.symbol).lineLimit(1)
                }
                Menu {
                    Picker(L("mode"), selection: Binding(get: { game.mode }, set: { game.switchMode($0) })) {
                        ForEach(GameMode.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(game.mode.title, systemImage: game.mode == .daily ? "calendar" : "shuffle").lineLimit(1)
                }
            }
            .font(.callout)
        }
    }
}

/// Apple TV tahmin girişi. Kutu seçilince tam ekran klavye açılır; kumandanın mikrofon düğmesiyle
/// dikte edilebilir. iPhone'daki Atlas "TV'ye söyle" ile adı sesle de gönderebilir (`VoiceHost`). Dikte adı tam doğru yazmayabilir ("Kahraman Maraş.", "la France"), bu yüzden
/// eşleştirme hoşgörülüdür: tek bir yere uyuyorsa doğrudan tahmin edilir, birkaç yere benziyorsa
/// seçmek için kısa bir liste çıkar.
struct TVGuessInput: View {
    let game: GameModel
    @State private var text = ""
    @State private var choices: [Place] = []
    @State private var voice = VoiceHost.shared
    @FocusState private var focused: Bool
    @AppStorage(AppSettings.showDistanceKey) private var showDistance = true
    #if DEBUG
    private static var debugHooksRan = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(L("placeholder.\(game.category.kind)"), text: $text)
                .focused($focused)
                .onSubmit { submit() }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            if choices.isEmpty {
                Label(L(voice.connectedCount > 0 ? "tv.phoneConnected" : "tv.phoneHint"),
                      systemImage: voice.connectedCount > 0 ? "iphone.radiowaves.left.and.right" : "mic.fill")
                    .font(.caption)
                    .foregroundStyle(voice.connectedCount > 0 ? AnyShapeStyle(ColorScale.found) : AnyShapeStyle(.secondary))
            } else {
                Text(L("tv.didYouMean"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(choices, id: \.id) { p in
                    Button { guess(p) } label: {
                        HStack {
                            Text(p.name)
                            Spacer()
                            if game.category == .turkey {
                                Text(p.code).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            focused = true
            #if DEBUG
            // Geliştirme: dikte eşleştirmesini simülatörde denemek için ("|" ile ayrılmış metinler).
            // ATLAS_VOICETEST sonuçları konsola yazar, ATLAS_GUESSES metinleri sırayla gönderir.
            // Tahmin kutusu her yeni oyunda yeniden açıldığı için kancalar yalnızca bir kez çalışır.
            guard !Self.debugHooksRan else { return }
            Self.debugHooksRan = true
            let env = ProcessInfo.processInfo.environment
            for t in env["ATLAS_VOICETEST"]?.split(separator: "|") ?? [] {
                FileHandle.standardError.write(Data("VOICE \(t) → \(game.places.voiceMatch(String(t)) { _ in true })\n".utf8))
            }
            if env["ATLAS_PRACTICE"] != nil { game.newPractice() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                for t in env["ATLAS_GUESSES"]?.split(separator: "|") ?? [] {
                    text = String(t)
                    submit()
                }
                // ATLAS_WIN: sonuç penceresini ve seviye kartını denemek için gizli yeri tahmin eder.
                if env["ATLAS_WIN"] != nil { _ = game.submit(game.answer) }
            }
            // ATLAS_SWITCH="europe@8": 8 sn sonra kategoriyi değiştirir (telefon bağlıyken kategori geçişini denemek için).
            if let sw = env["ATLAS_SWITCH"]?.split(separator: "@"), let c = GameCategory(rawValue: String(sw[0])) {
                DispatchQueue.main.asyncAfter(deadline: .now() + (Double(sw.last ?? "") ?? 8)) { game.switchCategory(c) }
            }
            #endif
        }
        .onChange(of: game.roundID) { text = ""; choices = []; focused = true }
        .onChange(of: voice.incoming?.id) {
            if let spoken = voice.incoming, !game.isOver {
                voice.handledID = spoken.id
                fromPhone(spoken.text, alternatives: spoken.alternatives)
            }
        }
    }

    /// iPhone'dan gelen ad: kutuya yazılır, aynı eşleştirmeyle tahmin edilir, sonuç telefona döner.
    /// Tanıyıcının ilk yazımı bir yere uymuyorsa diğer olası yazımlarından tam uyan ilki kullanılır.
    private func fromPhone(_ spoken: String, alternatives: [String] = []) {
        #if DEBUG
        FileHandle.standardError.write(Data("PHONE \(game.category.rawValue) ← \(spoken) \(alternatives)\n".utf8))
        #endif
        guard !game.isOver else {
            voice.reply(L("voice.gameOver"))
            return
        }
        text = spoken
        submit(alternatives: alternatives)
        if !choices.isEmpty {
            voice.reply(L("tv.didYouMean") + " " + choices.map(\.name).joined(separator: " · "))
        } else if game.status == .won {
            voice.reply("\(L("over.won")) \(game.answer.name)")
        } else if let message = game.message {
            voice.reply(message)
        } else if let last = game.lastGuess {
            voice.reply(guessFeedback(last, category: game.category, showDistance: showDistance))
        }
    }

    private func submit(alternatives: [String] = []) {
        let result = game.places.voiceMatch([text] + alternatives) { game.guess(for: $0) == nil }
        switch result {
        case .exact(let place):
            guess(place)
        case .choices(let list):
            choices = list
        case .none:
            choices = []
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { game.submit(text) }
        }
    }

    private func guess(_ place: Place) {
        if game.submit(place) { text = "" }
        choices = []
        focused = true
    }
}

/// iPhone'daki "TV'ye söyle" ile TV'deki oyun arasındaki köprü. Tahmin kutusu oyun bitince ekrandan
/// kalktığı için ipucu, yeni oyun ve pes et istekleri ile oyun durumu burada, hep ekranda olan düzende işlenir.
struct TVVoiceBridge: ViewModifier {
    let game: GameModel
    @State private var voice = VoiceHost.shared

    private var hintsLeft: Int { game.isOver ? 0 : game.hints.count - game.hintsUsed }

    func body(content: Content) -> some View {
        content
            .onAppear {
                voice.start()
                sync()
            }
            .onChange(of: game.category) { sync() }
            .onChange(of: hintsLeft) { sync() }
            .onChange(of: game.isOver) { sync() }
            .onChange(of: voice.incoming?.id) {
                // Oyun sürerken adları tahmin kutusu (`TVGuessInput`) işler; o işlemediyse oyun bitmiştir.
                guard let id = voice.incoming?.id else { return }
                DispatchQueue.main.async {
                    if voice.handledID != id { voice.reply(L("voice.gameOver")) }
                }
            }
            .onChange(of: voice.command?.id) {
                guard let kind = voice.command?.kind else { return }
                switch kind {
                case .hint: hint()
                case .newGame:
                    guard game.isOver else { return }
                    game.showResult = false
                    game.newPractice()
                case .setCategory:
                    if let c = voice.command?.category.flatMap(GameCategory.init(rawValue:)) { game.switchCategory(c) }
                case .giveUp:
                    guard !game.isOver else { return }
                    game.giveUp()
                    voice.reply("\(L("over.hidden.\(game.category.kind)")) \(game.answer.name)")
                default: break
                }
            }
    }

    private func sync() {
        voice.category = game.category.rawValue
        voice.hintsLeft = hintsLeft
        voice.isOver = game.isOver
    }

    /// Telefondaki ampul: sıradaki ipucunu açar, metnini telefona yollar.
    private func hint() {
        guard !game.isOver else { voice.reply(L("voice.gameOver")); return }
        guard hintsLeft > 0 else { voice.reply(L("voice.noHints")); return }
        withAnimation { game.useHint() }
        sync()
        voice.reply("💡 " + game.hints[game.hintsUsed - 1])
    }
}

enum VoiceMatch: Equatable, CustomStringConvertible {
    case exact(Place)
    case choices([Place])
    case none

    var description: String {
        switch self {
        case .exact(let p): "tam: \(p.trName)"
        case .choices(let list): "seçenek: \(list.map(\.trName).joined(separator: ", "))"
        case .none: "yok"
        }
    }
}

extension PlaceSet {
    /// Diktenin başa eklediği tanımlıklar ("the Netherlands", "la France", "il Brasile").
    private static let articles: Set<String> = ["the", "der", "die", "das", "le", "la", "les", "l", "el", "los", "las",
                                                "il", "lo", "gli", "i"]

    /// Konuşarak yazılan metni bir yere eşler. `isOpen` henüz tahmin edilmemiş yerleri seçer.
    func voiceMatch(_ text: String, isOpen: (Place) -> Bool) -> VoiceMatch {
        voiceMatch([text], isOpen: isOpen)
    }

    /// Tanıyıcının birkaç olası yazımını (önce en olası) birlikte değerlendirir.
    func voiceMatch(_ texts: [String], isOpen: (Place) -> Bool) -> VoiceMatch {
        var variants: [String] = []
        var words: [String] = []
        for text in texts {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !t.isEmpty else { continue }
            variants.append(t)
            let parts = t.split(whereSeparator: { $0 == " " || $0 == "'" || $0 == "’" }).map(String.init)
            if parts.count > 1, Self.articles.contains(parts[0].lowercased()) {
                variants.append(parts.dropFirst().joined(separator: " "))
            }
            // "Kars ili", "Fransa'yı": tek tek kelimeler ve ikili kelime grupları da denenir.
            if parts.count > 1 {
                words += parts.filter { $0.count >= 3 }
                words += zip(parts, parts.dropFirst()).map { "\($0) \($1)" }
            }
        }

        // 1. Ad, başka dildeki ad, takma ad ya da plaka kodu tam uyuyor.
        for v in variants + words {
            if let place = match(v) { return .exact(place) }
        }
        // 2. Yazılan, tek bir açık yerin adının başı ya da parçası.
        for v in variants {
            let list = suggestions(for: v, limit: 4).filter(isOpen)
            if list.count == 1 { return .exact(list[0]) }
            if !list.isEmpty { return .choices(list) }
        }
        // 3. Dikte birkaç harf yanlış duymuş olabilir: sesçe sadeleştirilmiş adlara harf farkıyla en yakın olanlar.
        let keys = Array(Set((variants + words).map { Self.phonetic(TurkishText.normalize($0)) }.filter { $0.count >= 3 }))
        var scored: [(place: Place, d: Int, len: Int)] = []
        for p in places where isOpen(p) {
            var best: (d: Int, len: Int)?
            for key in keys {
                for s in p.searchKeys {
                    let ps = Self.phonetic(s)
                    let d = Self.editDistance(key, ps)
                    if d <= max(1, ps.count / 3), d < best?.d ?? .max { best = (d, ps.count) }
                }
            }
            if let best { scored.append((p, best.d, best.len)) }
        }
        scored.sort { $0.d != $1.d ? $0.d < $1.d : $0.place.name < $1.place.name }
        guard let first = scored.first else { return .none }
        // Tek aday ya da açık ara en yakın aday doğrudan tahmin edilir; yoksa seçim listesi.
        if scored.count == 1 || (first.d < scored[1].d && first.d <= max(1, first.len / 5)) {
            return .exact(first.place)
        }
        return .choices(scored.prefix(4).map(\.place))
    }

    /// Kulağa benzer yazımları eşitler: çift harfler teke, ph → f, w → v, q → k, x → ks.
    static func phonetic(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "ph", with: "f")
            .replacingOccurrences(of: "w", with: "v")
            .replacingOccurrences(of: "q", with: "k")
            .replacingOccurrences(of: "x", with: "ks")
        var out = ""
        for c in t where c != out.last { out.append(c) }
        t = out
        return t
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var prev = row[0]
            row[0] = i
            for j in 1...b.count {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return row[b.count]
    }
}
#endif
