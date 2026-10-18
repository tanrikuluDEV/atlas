import SwiftUI

@main
struct AtlasApp: App {
    @State private var game = GameModel()
    @State private var showStats = false
    @State private var showHelp = false
    @State private var l10n = L10n.shared

    init() {
        Brand.registerFonts()
        #if DEBUG && os(macOS)
        DebugSnapshots.runIfRequested()
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        Window("Atlas", id: "main") {
            ContentView(game: game, showStats: $showStats, showHelp: $showHelp)
        }
        .defaultSize(width: 1180, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("newPractice")) { game.newPractice() }
                    .keyboardShortcut("n")
                Button(L("dailyPuzzle")) { game.switchMode(.daily) }
                    .keyboardShortcut("d")
            }
            CommandMenu(L("category")) {
                ForEach(Array(GameCategory.allCases.enumerated()), id: \.element) { i, c in
                    Toggle(isOn: Binding(get: { game.category == c }, set: { if $0 { game.switchCategory(c) } })) {
                        Label(c.title, systemImage: c.symbol)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
            }
            CommandMenu(L("game")) {
                Button(L("stats")) { showStats = true }
                    .keyboardShortcut("i")
                Button(L("giveUp")) { game.giveUp() }
                    .disabled(game.isOver || game.guesses.isEmpty)
            }
            CommandMenu(L("language")) {
                Picker(L("language"), selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { Text("\($0.flag) \($0.nativeName)").tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            CommandGroup(replacing: .help) {
                Button(L("help")) { showHelp = true }
                    .keyboardShortcut("?")
            }
        }

        Settings {
            SettingsView()
                .environment(\.locale, l10n.language.locale)
        }
        #else
        WindowGroup {
            ContentView(game: game, showStats: $showStats, showHelp: $showHelp)
        }
        #endif
    }
}
