import SwiftUI

struct ContentView: View {
    @Bindable var game: GameModel
    @Binding var showStats: Bool
    @Binding var showHelp: Bool
    @AppStorage("helpSeen") private var helpSeen = false
    @State private var showSettings = false
    @State private var showVoiceRemote = false
    @State private var showCategories = false
    @State private var confettiStart: Date?
    /// Açılış animasyonu; `-renderSnapshots` ile ekran dışı çizimde atlanır.
    @State private var showSplash = !ProcessInfo.processInfo.arguments.contains("-renderSnapshots")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var l10n = L10n.shared

    private let dayTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            #if os(macOS) || os(tvOS)
            content
            #else
            NavigationStack {
                content
                    .navigationBarTitleDisplayMode(.inline)
            }
            #endif
        }
        // Büyük harfe çevirme, tarih ve sayı biçimleri seçili dile uysun (Türkçede "i" → "İ").
        .environment(\.locale, l10n.language.locale)
        // Bağlantılar, düğmeler ve seçimler sistem vurgusu yerine marka turuncusuyla.
        .tint(Brand.accent)
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            MapView(game: game)
                .frame(minWidth: 520, minHeight: 420)
            Divider()
            Sidebar(game: game)
                .frame(width: 320)
        }
        #elseif os(tvOS)
        // Apple TV: harita ekranın solunu köşeden köşeye kaplar; sağda dar bir sütunda başlık, eylemler ve panel.
        HStack(spacing: 0) {
            MapView(game: game)
                .ignoresSafeArea(edges: [.leading, .top, .bottom])
            VStack(alignment: .leading, spacing: 24) {
                TVHeader(game: game, showStats: $showStats, showHelp: $showHelp, showSettings: $showSettings)
                Sidebar(game: game)
            }
            .frame(width: 480)
            .padding(.leading, 40)
        }
        .modifier(TVVoiceBridge(game: game))
        #else
        VStack(spacing: 0) {
            MapView(game: game)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .background(Color(white: 0.5).opacity(0.06))
            Divider()
            Sidebar(game: game)
        }
        // Klavye açılınca düzen yeniden sıkıştırılmasın: yoksa öneri listesi uzayıp kısaldıkça
        // harita yukarı aşağı kayar. Listenin alt satırları klavyenin altında kalabilir.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        #endif
    }

    private var content: some View {
        layout
        #if !os(tvOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                // Kartlı kategori seçici: Mac'te balon, iPhone'da sayfa.
                Button { showCategories = true } label: {
                    Label(game.category.title, systemImage: game.category.symbol)
                        #if os(macOS)
                        .labelStyle(.titleAndIcon)
                        #endif
                }
                .help(L("category"))
                .accessibilityLabel("\(L("category")): \(game.category.title)")
                #if os(macOS)
                .popover(isPresented: $showCategories, arrowEdge: .bottom) {
                    CategoryPicker(game: game, isPresented: $showCategories)
                }
                #endif
            }
            ToolbarItem(placement: .principal) {
                #if os(macOS)
                Picker(L("mode"), selection: Binding(get: { game.mode }, set: { game.switchMode($0) })) {
                    ForEach(GameMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
                #else
                // iPhone'da dört mod dar araç çubuğuna sığmaz; seçili mod bir menü olarak görünür.
                Menu {
                    Picker(L("mode"), selection: Binding(get: { game.mode }, set: { game.switchMode($0) })) {
                        ForEach(GameMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: game.mode.symbol)
                        Text(game.mode.title).fontWeight(.semibold)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                }
                .accessibilityLabel("\(L("mode")): \(game.mode.title)")
                #endif
            }
            #if os(macOS)
            ToolbarItemGroup(placement: .primaryAction) {
                languageMenu
                if game.mode != .daily {
                    Button { game.newRound() } label: { Label(L("newGame"), systemImage: "arrow.clockwise") }
                        .help("\(L("newGame")) (⌘N)")
                }
                Button { showStats = true } label: { Label(L("stats"), systemImage: "chart.bar.fill") }
                    .help(L("stats"))
                Button { showHelp = true } label: { Label(L("help"), systemImage: "questionmark.circle") }
                    .help(L("help"))
            }
            #else
            // iPhone'da dar araç çubuğu: dil bayrakla, diğer eylemler tek bir menüde.
            ToolbarItemGroup(placement: .primaryAction) {
                languageMenu
                Menu {
                    if game.mode != .daily {
                        Button { game.newRound() } label: { Label(L("newGame"), systemImage: "arrow.clockwise") }
                    }
                    Button { showStats = true } label: { Label(L("stats"), systemImage: "chart.bar.fill") }
                    Button { showVoiceRemote = true } label: { Label(L("voice.title"), systemImage: "appletv") }
                    Button { showSettings = true } label: { Label(L("settings"), systemImage: "gearshape") }
                    Button { showHelp = true } label: { Label(L("help"), systemImage: "questionmark.circle") }
                } label: {
                    Label(L("menu"), systemImage: "ellipsis.circle")
                }
            }
            #endif
        }
        .navigationTitle(game.mode == .daily ? "Atlas #\(game.puzzleNumber)" : "Atlas · \(game.mode.title)")
        #if os(macOS)
        .navigationSubtitle(game.category.title)
        #endif
        #endif
        .sheet(isPresented: $game.showResult) { ResultView(game: game) }
        .sheet(isPresented: $showStats) { StatsView(game: game) }
        .sheet(isPresented: $showHelp) { HelpView() }
        #if os(iOS)
        .sheet(isPresented: $showVoiceRemote) { VoiceRemoteView() }
        .sheet(isPresented: $showCategories) { CategoryPicker(game: game, isPresented: $showCategories) }
        #endif
        #if os(iOS) || os(tvOS)
        .sheet(isPresented: $showSettings) { SettingsView() }
        #endif
        .onReceive(dayTimer) { _ in game.refreshDayIfNeeded() }
        #if os(iOS) || os(macOS)
        // Hatırlatmalar her açılışta yeniden kurulur (bugün oynandıysa bugünkü atlanır, seri metni güncellenir).
        .onAppear { Reminders.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Reminders.refresh() } }
        #endif
        #if DEBUG
        // Geliştirme: ATLAS_MODE=timed|chain, ATLAS_CATEGORY=europe, ATLAS_START (süreyi başlatır),
        // ATLAS_PLAY="Fransa|@route|@answer|@skip" (tahminler; @route zincirin en kısa rotası, @answer gizli yer).
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if let c = env["ATLAS_CATEGORY"].flatMap(GameCategory.init(rawValue:)) { game.switchCategory(c) }
            if let m = env["ATLAS_MODE"].flatMap(GameMode.init(rawValue:)) { game.switchMode(m) }
            if env["ATLAS_START"] != nil { game.startTimer() }
            guard let play = env["ATLAS_PLAY"] else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                for t in play.split(separator: "|").map(String.init) {
                    switch t {
                    case "@route": for p in game.chainShortest.dropFirst().dropLast() { game.submit(p) }
                    case "@answer": game.submit(game.answer)
                    case "@skip": game.skipTimed()
                    case "@giveup": game.giveUp()
                    default: game.submit(t)
                    }
                }
                if env["ATLAS_HIDE_RESULT"] != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { game.showResult = false } }
            }
        }
        #endif
        #if DEBUG && os(iOS)
        .onAppear {
            if ProcessInfo.processInfo.environment["ATLAS_VOICE_SEND"] != nil { showVoiceRemote = true }
            // Geliştirme: kategori seçiciyi açılışta açar (simülatörde ekran görüntüsü için).
            if ProcessInfo.processInfo.environment["ATLAS_SHOW"] == "categories" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCategories = true }
            }
        }
        #endif
        // Bulunca konfeti (yalnızca tahminle kazanıldığında; kayıtlı oyun açılınca değil).
        // Ses ve titreşim.
        .onChange(of: game.lastGuess) { _, guess in
            guard let guess else { return }
            if game.status == .won {
                GameFeedback.shared.won()
            } else {
                GameFeedback.shared.guessMade(proximity: game.feedbackProximity(of: guess),
                                              improved: game.lastImproved && (game.guesses.count > 1 || game.mode == .chain))
            }
        }
        .onChange(of: game.timedFound.count) { old, new in
            if new > old { GameFeedback.shared.won() }
        }
        .onChange(of: game.status) { old, new in
            if old == .playing && new == .lost { GameFeedback.shared.lost() }
        }
        .onChange(of: game.lastGuess) { _, guess in
            guard guess != nil, game.status == .won, !reduceMotion else { return }
            let start = Date()
            confettiStart = start
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                if confettiStart == start { confettiStart = nil }
            }
        }
        .overlay {
            if let confettiStart { ConfettiView(start: confettiStart) }
        }
        .overlay {
            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
                    // İlk açılışta yardım, açılış animasyonu bitince gelir.
                    if !helpSeen { helpSeen = true; showHelp = true }
                }
                .transition(.opacity)
            }
        }
    }
}

extension ContentView {
    /// Araç çubuğundaki dil seçici: yalnızca bayrak görünür, menüde dillerin kendi adları.
    var languageMenu: some View {
        Menu {
            Picker(L("language"), selection: $l10n.language) {
                ForEach(AppLanguage.allCases) { Text("\($0.flag) \($0.nativeName)").tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Text(l10n.language.flag)
                .font(.system(size: Platform.isMac ? 15 : 20))
                .accessibilityLabel(L("language"))
        }
        .menuIndicator(.hidden)
        .help(L("language"))
    }
}

// MARK: - Kenar çubuğu

private struct Sidebar: View {
    let game: GameModel
    @AppStorage(AppSettings.showDistanceKey) private var showDistance = true

    var body: some View {
        VStack(alignment: .leading, spacing: Platform.isMac ? 14 : 10) {
            // iPhone'da ekran alanı dar; yalnızca tek satırlık kategori bilgisi gösterilir.
            if !Platform.isMac && !Platform.isTV {
                HStack {
                    Label(game.mode.isClassic ? game.category.subtitle : "\(game.category.title) · \(panelTitle(game))",
                          systemImage: game.category.symbol)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if game.expert { Spacer(minLength: 4); ExpertTag() }
                }
            } else if Platform.isTV && game.expert {
                ExpertTag()
            }
            if Platform.isMac {
                VStack(alignment: .leading, spacing: 2) {
                    Label(game.category.title, systemImage: game.category.symbol)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(panelTitle(game))
                            .font(Brand.heading(.title2))
                        if game.expert { ExpertTag() }
                    }
                    Text(game.category.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if game.mode == .timed && !game.isOver && game.timedStart != nil { TimedBar(game: game) }
            if game.mode == .chain { ChainCard(game: game) }

            if game.mode == .chain && !game.chainAvailable {
                ChainUnavailableCard(game: game)
            } else if game.isOver {
                switch game.mode {
                case .timed: TimedOverBanner(game: game)
                case .chain: ChainOverBanner(game: game)
                default: GameOverBanner(game: game)
                }
            } else {
                #if os(tvOS)
                TVGuessInput(game: game)
                #else
                // Açılan öneri listesi alttaki içeriğin üstünde çizilsin.
                GuessInput(game: game).zIndex(1)
                #endif
            }

            if let message = game.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else if let last = game.lastGuess, !game.isOver {
                Text(feedback(for: last))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            if !game.expert && game.mode != .chain { HeatGauge(game: game) }

            if game.mode != .chain, let closest = game.closest, !game.isOver {
                HStack {
                    Text(L("closest"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Kilometre kapalıyken de komşuluk gösterilir; yalnızca km değeri gizlenir. Uzman modunda ikisi de gizli.
                    Text(game.expert ? closest.place.name
                         : closest.distance == 0 ? "\(closest.place.name) · \(L("neighbor"))"
                         : showDistance ? "\(closest.place.name) · \(TurkishText.formatKm(closest.distance))"
                         : closest.place.name)
                        .fontWeight(.semibold)
                }
                .font(.callout)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            switch game.mode {
            case .timed:
                if game.timedStart == nil && !game.isOver { TimedStartCard(game: game) }
                if !game.isOver { GuessList(game: game) }
                TimedFoundList(game: game)
            case .chain:
                // Oyun bitince rota bannerda yazılı; liste yer kaplamasın.
                if !game.isOver { ChainGuessList(game: game) }
            default:
                HintsSection(game: game)
                GuessList(game: game)
            }

            Spacer(minLength: 0)

            HStack {
                Text(footerText)
                    .foregroundStyle(.secondary)
                Spacer()
                if game.mode == .timed && !game.isOver && game.timedStart != nil {
                    Button(L("timed.skip")) { game.skipTimed() }
                        #if os(macOS)
                        .buttonStyle(.link)
                        .keyboardShortcut("s", modifiers: .command)
                        #else
                        .buttonStyle(.borderless)
                        #endif
                }
                if !game.isOver && (game.mode == .timed ? game.timedStart != nil : !game.guesses.isEmpty) {
                    Button(L(game.mode == .timed ? "timed.finish" : "giveUp"), role: .destructive) { game.giveUp() }
                        #if os(macOS)
                        .buttonStyle(.link)
                        #else
                        .buttonStyle(.borderless)
                        #endif
                }
            }
            .font(.callout)
        }
        .padding(Platform.isMac ? 18 : 14)
        #if !os(tvOS)
        .background(Brand.panel)
        #endif
        .animation(.default, value: game.message)
    }

    private func feedback(for guess: Guess) -> String {
        if game.mode == .chain { return L("chain.feedback.\(guess.distance)", ["name": guess.place.name]) }
        return guessFeedback(guess, category: game.category, showDistance: showDistance, expert: game.expert)
    }

    private var footerText: String {
        switch game.mode {
        case .timed: L("timed.score", ["n": game.timedFound.count])
        default: L("guesses", ["n": game.guesses.count])
        }
    }
}

/// Paneldeki başlık: moda göre.
func panelTitle(_ game: GameModel) -> String {
    switch game.mode {
    case .daily: L("panel.daily.\(game.category.kind)")
    case .practice: L("mode.practice")
    case .timed: L("timed.title")
    case .chain: L("chain.title")
    }
}

/// Uzman modunda panelde görünen küçük etiket.
struct ExpertTag: View {
    var body: some View {
        Label(L("expert.tag"), systemImage: "eye.slash.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Brand.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Brand.accent.opacity(0.12), in: Capsule())
            .help(L("set.expertHint"))
    }
}

/// Son tahminin panelde (ve Apple TV'den iPhone'a giden yanıtta) gösterilen açıklaması.
func guessFeedback(_ guess: Guess, category: GameCategory, showDistance: Bool, expert: Bool = false) -> String {
    let kind = category.kind
    if expert { return L("feedback.colored", ["name": guess.place.name]) }
    if guess.distance == 0 { return L("feedback.neighbor.\(kind)", ["name": guess.place.name]) }
    guard showDistance else { return L("feedback.colored", ["name": guess.place.name]) }
    return L("feedback.distance.\(kind)", ["name": guess.place.name, "km": TurkishText.formatKm(guess.distance)])
}

/// Açılan ipuçları ve "İpucu al" düğmesi; oyun bitince üç ipucu da "Bu yer hakkında" olarak görünür.
private struct HintsSection: View {
    let game: GameModel

    var body: some View {
        let hints = game.hints
        let shown = game.isOver ? hints : Array(hints.prefix(game.hintsUsed))
        if !hints.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !shown.isEmpty {
                    Text(L(game.isOver ? "hints.about" : "hints.header"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, hint in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(i + 1).").foregroundStyle(.secondary).monospacedDigit()
                            Text(hint).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout)
                    }
                }
                if !game.isOver && game.hintsUsed < hints.count {
                    Button {
                        withAnimation { game.useHint() }
                    } label: {
                        Label(L("hint.take", ["n": hints.count - game.hintsUsed]), systemImage: "lightbulb")
                    }
                    #if os(macOS)
                    .buttonStyle(.link)
                    #else
                    .buttonStyle(.borderless)
                    #endif
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GameOverBanner: View {
    let game: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(game.status == .won ? L("over.won") : L("over.hidden.\(game.category.kind)"), systemImage: game.status == .won ? "checkmark.seal.fill" : "flag.fill")
                .font(.headline)
                .foregroundStyle(game.status == .won ? ColorScale.found : ColorScale.answerReveal)
            HStack(spacing: 8) {
                FlagView(place: game.answer, height: 22)
                Text(game.answer.name)
            }
            .font(Brand.heading(.title))
            HStack {
                Button(L("result")) { game.showResult = true }
                Button(L("newGame")) { game.newRound() }
                    .defaultActionShortcut()
            }
            Button {
                if game.replayStep == nil { game.startReplay() } else { game.stopReplay() }
            } label: {
                Label(L(game.replayStep == nil ? "replay.button" : "replay.stop"),
                      systemImage: game.replayStep == nil ? "play.circle" : "stop.circle")
            }
            #if os(macOS)
            .buttonStyle(.link)
            #elseif os(iOS)
            .buttonStyle(.borderless)
            #endif
            .disabled(game.replayLength == 0)

            if game.mode == .daily {
                Divider().padding(.vertical, 2)
                DailyCountdown()
                    .font(.callout)
                    .foregroundStyle(.secondary)
                OtherDailies(game: game)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Tahmin girişi

#if !os(tvOS)
private struct GuessInput: View {
    let game: GameModel
    @State private var text = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var suggestions: [Place] {
        game.places.suggestions(for: text).filter { game.guess(for: $0) == nil }
    }

    var body: some View {
        HStack(spacing: 8) {
                TextField(L("placeholder.\(game.category.kind)"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: text) { highlighted = 0 }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.escape) { text = ""; return .handled }
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.go)
                    #endif
                Button(L("guess"), action: submit)
                    .controlSize(.large)
                    #if os(iOS)
                    .buttonStyle(.borderedProminent)
                    #endif
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        // Öneriler düzenin parçası değil, kutunun hemen altında açılan bir katman: liste uzayıp
        // kısaldıkça harita ve diğer içerik kaymaz. Uzun listenin sonu klavyenin altında kalabilir.
        .overlay(alignment: .bottomLeading) {
            suggestionList
                .alignmentGuide(.bottom) { d in d[.top] - 4 }
        }
        .onAppear {
            focusSoon()
            #if DEBUG
            // Geliştirme: öneri listesini ekran görüntüsünde test etmek için kutuyu önceden doldurur.
            if let prefill = ProcessInfo.processInfo.environment["ATLAS_PREFILL"] { text = prefill }
            #endif
        }
        .onChange(of: game.roundID) { text = ""; focusSoon() }
    }

    @ViewBuilder
    private var suggestionList: some View {
        let items = suggestions
        // Yazılan metin zaten tek bir ile tam uyuyorsa öneri listesine gerek yok.
        if !items.isEmpty && !(items.count == 1 && game.places.match(text) == items[0]) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, p in
                        Button { guess(p) } label: {
                            HStack(spacing: 6) {
                                FlagView(place: p)
                                Text(p.name)
                                Spacer()
                                if game.category == .turkey {
                                    Text(p.code).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, Platform.isMac ? 6 : 10)
                            .contentShape(Rectangle())
                            .background(i == highlighted ? Brand.accent.opacity(0.16) : .clear)
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { highlighted = i } }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
    }

    /// Odak, sonuç sayfası kapanıp pencere yeniden klavyeyi alana kadar kısa bir süre bekletilir;
    /// hemen istenirse kapanmakta olan sayfa odağı yutar.
    private func focusSoon() {
        focused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let count = suggestions.count
        guard count > 0 else { return .ignored }
        highlighted = (highlighted + delta + count) % count
        return .handled
    }

    private func submit() {
        if let exact = game.places.match(text) {
            guess(exact)
        } else if suggestions.indices.contains(highlighted) {
            guess(suggestions[highlighted])
        } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            game.submit(text)
        }
    }

    private func guess(_ place: Place) {
        if game.submit(place) { text = "" }
        focused = true
    }
}

#endif

// MARK: - Tahmin listesi

private struct GuessList: View {
    let game: GameModel

    var body: some View {
        if game.guesses.isEmpty {
            if !game.isOver && game.mode.isClassic { EmptyRoundCard(game: game) }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("guesses.header"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(game.sortedGuesses) { g in
                            GuessRow(guess: g, isAnswer: g.place == game.answer, maxDistance: game.places.maxDistance,
                                     isSelected: game.highlighted == g.place, expert: game.expert && !game.isOver) {
                                // Uzman modunda oyun sürerken yer haritada gösterilmez.
                                guard game.showsGuessNames else { return }
                                game.highlighted = game.highlighted == g.place ? nil : g.place
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct GuessRow: View {
    let guess: Guess
    let isAnswer: Bool
    let maxDistance: Int
    let isSelected: Bool
    /// Uzman modunda yalnızca renk görünür.
    var expert = false
    let onSelect: () -> Void
    @AppStorage(AppSettings.showDistanceKey) private var showDistance = true

    var body: some View {
        Button(action: onSelect) { row }
            .buttonStyle(.plain)
            .help(L(isSelected ? "highlight.remove" : "highlight.show"))
    }

    private var row: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(isAnswer ? ColorScale.found : ColorScale.color(forDistance: guess.distance, max: maxDistance))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.1)))
                .frame(width: 18, height: 18)
            HStack(spacing: 6) {
                FlagView(place: guess.place)
                Text(guess.place.name)
                    .fontWeight(isAnswer ? .bold : .regular)
            }
            Spacer()
            if isAnswer || (!expert && (showDistance || guess.distance == 0)) {
                Text(isAnswer ? L("found") : guess.distance == 0 ? L("Neighbor") : TurkishText.formatKm(guess.distance))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? AnyShapeStyle(ColorScale.highlight.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.35)),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? ColorScale.highlight : .clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
