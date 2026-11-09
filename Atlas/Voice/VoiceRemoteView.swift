#if os(iOS)
import SwiftUI

/// iPhone'da "TV'ye söyle": büyük mikrofon düğmesine basılı tutup adı söyle, bırakınca Apple TV'ye gider.
struct VoiceRemoteView: View {
    @State private var remote = VoiceRemote()
    @State private var pressing = false
    /// Önceden hazırlanmış titreşim üreteçleri: anında tepki versin diye (her basışta yeni üreteç gecikiyordu).
    @State private var pressHaptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var releaseHaptic = UIImpactFeedbackGenerator(style: .light)
    /// Pes et ilk basışta onay ister; birkaç saniye içinde ikinci basış gerekir.
    @State private var confirmGiveUp = false
    @State private var nameDraft = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 10) {
                    newGameButton
                    if remote.connection == .connected && remote.tvOver && remote.tvCanReplay { replayButton }
                    Spacer(minLength: 0)
                    hintButton
                }
                status
                if remote.connection == .connected && remote.party { partyBox }
                Spacer()
                micButton
                Text(caption)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 56)
                if let reply = remote.reply {
                    Text(reply)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity)
                }
                Spacer()
                giveUpButton
                Text(L("voice.footer"))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .ignoresSafeArea(.keyboard)
            .animation(.default, value: remote.reply)
            // Sayfa aşağı çekilince kapanma hareketi mikrofon düğmesinin dokunuşunu geciktirmesin.
            .interactiveDismissDisabled()
            .navigationTitle(L("voice.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("done")) { dismiss() } }
            }
        }
        .onAppear {
            remote.start()
            pressHaptic.prepare()
            // Arkadaki tahmin kutusunun klavyesi bu sayfanın altını kapatmasın (sayfa açılınca kapatılır).
            hideKeyboard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { hideKeyboard() }
        }
        #if DEBUG
        // Geliştirme: ATLAS_VOICE_SEND="Ankara|Merhaba/Kars|hint|giveup|newgame" bağlanınca sırayla gönderir ("/" sonrası alternatif yazımlar; hint, giveup, newgame = düğmeler).
        .onChange(of: remote.connection) {
            guard remote.connection == .connected,
                  let list = ProcessInfo.processInfo.environment["ATLAS_VOICE_SEND"]?.split(separator: "|") else { return }
            for (i, t) in list.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i) * 1.5) {
                    switch t {
                    case "hint": remote.requestHint()
                    case "giveup": remote.requestGiveUp()
                    case "newgame": remote.requestNewGame()
                    case "replay": remote.requestReplay()
                    case let c where c.hasPrefix("mode:"):
                        if let m = GameMode(rawValue: String(c.dropFirst(5))) { remote.requestMode(m) }
                    case let c where c.hasPrefix("name:"): remote.playerName = String(c.dropFirst(5))
                    case let c where c.hasPrefix("cat:"):
                        if let cat = GameCategory(rawValue: String(c.dropFirst(4))) { remote.requestCategory(cat) }
                    default: remote.debugSend(String(t))
                    }
                }
            }
        }
        #endif
        .onDisappear { remote.stop() }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Parti modu: sıra kimde, skorlar ve bu telefonun adı.
    private var partyBox: some View {
        VStack(spacing: 8) {
            Text(remote.yourTurn ? L("party.yourTurn") : L("party.turnOf", ["name": remote.turn ?? "…"]))
                .font(.title3.weight(.bold))
                .foregroundStyle(remote.yourTurn ? ColorScale.found : .secondary)
            HStack(spacing: 14) {
                ForEach(remote.partyPlayers, id: \.name) { p in
                    VStack(spacing: 0) {
                        Text("\(p.score)").font(Brand.heading(.title3)).monospacedDigit()
                        Text(p.name).font(.caption).lineLimit(1)
                            .fontWeight(p.name == remote.turn ? .bold : .regular)
                    }
                }
            }
            HStack(spacing: 6) {
                Text(L("party.yourName")).font(.footnote).foregroundStyle(.secondary)
                TextField(L("party.namePlaceholder"), text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.footnote)
                    .frame(maxWidth: 160)
                    .submitLabel(.done)
                    .onSubmit { remote.playerName = nameDraft.trimmingCharacters(in: .whitespaces) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Brand.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { nameDraft = remote.playerName }
        .onChange(of: remote.playerName) { nameDraft = remote.playerName }
    }

    private var status: some View {
        VStack(spacing: 6) {
            statusLine
            // TV'deki kategori: adlar bu kategoride aranır; buradan TV'nin kategorisi değiştirilir.
            // TV'deki mod da buradan değiştirilir.
            if remote.connection == .connected, let c = remote.tvCategory {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { categoryMenu(c); modeMenu }
                    VStack(spacing: 8) { categoryMenu(c); modeMenu }
                }
            }
        }
    }

    private func categoryMenu(_ c: GameCategory) -> some View {
        Menu {
            Picker(L("category"), selection: Binding(get: { c }, set: { remote.requestCategory($0) })) {
                ForEach(GameCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
        } label: {
            menuLabel(c.title, symbol: c.symbol)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var modeMenu: some View {
        if let m = remote.tvMode {
            Menu {
                Picker(L("mode"), selection: Binding(get: { m }, set: { remote.requestMode($0) })) {
                    ForEach(GameMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            } label: {
                menuLabel(m.title, symbol: m.symbol)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(L("mode")): \(m.title)")
        }
    }

    private func menuLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: symbol).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption)
        }
        .font(.headline)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .fixedSize()
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            switch remote.connection {
            case .connected:
                Image(systemName: "appletv.fill").foregroundStyle(ColorScale.found)
                Text(remote.tvName.map { "\(L("voice.connected")) · \($0)" } ?? L("voice.connected"))
            case .connecting, .searching:
                ProgressView()
                Text(L("voice.searching"))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var caption: String {
        switch remote.listening {
        case .denied: return L("voice.denied")
        case .unavailable: return L("voice.unavailable")
        case .listening: return remote.transcript.isEmpty ? L("voice.listening") : remote.transcript
        case .idle: return remote.transcript.isEmpty ? L("voice.hold") : remote.transcript
        }
    }

    private var micButton: some View {
        // Parti modunda yalnızca sıra bu telefondayken konuşulur.
        let enabled = remote.connection == .connected && (!remote.party || remote.yourTurn)
        return ZStack {
            Circle()
                .fill(Brand.orange.opacity(pressing ? 0.25 : 0))
                .frame(width: 220, height: 220)
                .scaleEffect(pressing ? 1.1 : 0.8)
            Circle()
                .fill(enabled ? Brand.orange : Color.gray.opacity(0.4))
                .frame(width: 160, height: 160)
                .shadow(color: Brand.orange.opacity(enabled ? 0.4 : 0), radius: pressing ? 24 : 10)
            Image(systemName: "mic.fill")
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(Brand.navy)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressing)
        .contentShape(Circle())
        // Basılı tutulduğu sürece dinler; bırakınca gönderir.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !pressing else { return }
                    pressing = true
                    pressHaptic.impactOccurred(intensity: 1)
                    releaseHaptic.prepare()
                    remote.beginListening()
                }
                .onEnded { _ in
                    guard pressing else { return }
                    pressing = false
                    releaseHaptic.impactOccurred()
                    pressHaptic.prepare()
                    remote.endListening()
                }
        )
        .accessibilityLabel(L("voice.hold"))
        .accessibilityAddTraits(.isButton)
    }

    /// Sol üst: TV'deki oyun bitince yeni oyun başlatır (oyun sürerken görünmez).
    private var newGameButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            remote.requestNewGame()
        } label: {
            Label(L("newGame"), systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.navy)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Brand.orange, in: Capsule())
        }
        .buttonStyle(.plain)
        .opacity(remote.connection == .connected && remote.tvOver ? 1 : 0)
        .disabled(!(remote.connection == .connected && remote.tvOver))
        .animation(.default, value: remote.tvOver)
        .fixedSize()
    }

    /// "Yeni oyun"un yanında: TV'de rotayı izletir (yalnızca günlük ve alıştırmada, oyun bitince); izlenirken "Durdur".
    private var replayButton: some View {
        let title = L(remote.tvReplaying ? "replay.stop" : "replay.button")
        let symbol = remote.tvReplaying ? "stop.circle.fill" : "play.circle.fill"
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            remote.requestReplay()
        } label: {
            // Dar ekranda (uzun dillerde) yalnızca simge kalır.
            ViewThatFits(in: .horizontal) {
                Label(title, systemImage: symbol).fixedSize()
                Image(systemName: symbol)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Brand.orange.opacity(0.25), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .transition(.opacity)
    }

    /// Küçük "Pes et": ilk basış onay ister, 3 sn içinde ikinci basış TV'de pes eder.
    private var giveUpButton: some View {
        let visible = remote.connection == .connected && !remote.tvOver
        return Button {
            if confirmGiveUp {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                confirmGiveUp = false
                remote.requestGiveUp()
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                confirmGiveUp = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmGiveUp = false }
            }
        } label: {
            Label(L(confirmGiveUp ? "voice.giveUpConfirm" : "giveUp"), systemImage: "flag.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(confirmGiveUp ? .white : .red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(confirmGiveUp ? Color.red : Color.red.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: confirmGiveUp)
        .opacity(visible ? 1 : 0)
        .disabled(!visible)
    }

    /// Sağ üst ampul: TV'deki oyunda sıradaki ipucunu açar; kalan sayı rozet olarak görünür.
    private var hintButton: some View {
        let enabled = remote.connection == .connected && remote.hintsLeft > 0
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            remote.requestHint()
        } label: {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(enabled ? Brand.navy : .secondary)
                .frame(width: 64, height: 64)
                .background(enabled ? Color.yellow : Color.gray.opacity(0.25), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if remote.connection == .connected {
                        Text("\(remote.hintsLeft)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Brand.orange, in: Circle())
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(L("hint.take", ["n": remote.hintsLeft]))
    }
}
#endif
