#if os(iOS) || os(tvOS)
import Foundation
import Network
import Observation

/// iPhone'u Apple TV için mikrofon olarak kullanma. Apple TV kumandasındaki mikrofon düğmesi Siri'ye
/// ayrılmış; uygulamalar onu ve kumandanın mikrofonunu kullanamaz. Bu yüzden iPhone'daki Atlas adı
/// dinleyip yazıya çevirir ve aynı ağdaki Apple TV'ye gönderir: TV Bonjour ile kendini duyurur,
/// iPhone bulup TCP ile bağlanır; mesajlar satır satır JSON. (MultipeerConnectivity'nin UDP kanalı
/// simülatörler arasında kurulamadığı için Network çerçevesi seçildi.)
enum VoiceLink {
    /// Info.plist'teki NSBonjourServices ile aynı olmalı.
    static let bonjourType = "_atlas-voice._tcp"

    struct Message: Codable {
        enum Kind: String, Codable {
            /// TV → iPhone: bağlanınca ve kategori değişince; tanımaya ipucu olacak yer adları için.
            case hello
            /// iPhone → TV: söylenen ad.
            case guess
            /// TV → iPhone: tahminin sonucu ("Ankara: gizli ile en yakın sınır 300 km").
            case reply
            /// iPhone → TV: sıradaki ipucunu aç.
            case hint
            /// iPhone → TV: oyun bittiyse yeni (alıştırma) oyunu başlat.
            case newGame
            /// iPhone → TV: pes et (telefonda iki basışla onaylanır).
            case giveUp
            /// iPhone → TV: kategoriyi değiştir (`category`).
            case setCategory
        }
        var kind: Kind
        var text: String?
        var category: String?
        /// iPhone → TV: tanıyıcının diğer olası yazımları (`text` yere uymazsa sırayla denenir).
        var alternatives: [String]?
        /// TV → iPhone: kalan ipucu sayısı (ampul düğmesi için; oyun bitince 0).
        var hintsLeft: Int?
        /// TV → iPhone: oyun bitti mi (yeni oyun / pes et düğmeleri için).
        var over: Bool?
    }

    /// Tek bir TCP bağlantısı: mesajları satır sonuyla ayırarak gönderir ve okur. Tüm geri çağrılar ana kuyrukta.
    final class Channel {
        private let connection: NWConnection
        private var buffer = Data()
        private(set) var isReady = false
        var onReady: (() -> Void)?
        var onClose: (() -> Void)?
        var onMessage: ((Message) -> Void)?

        init(_ connection: NWConnection) { self.connection = connection }

        func start() {
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isReady = true
                    self.onReady?()
                case .failed, .cancelled:
                    self.isReady = false
                    self.onClose?()
                    self.onClose = nil
                default:
                    break
                }
            }
            connection.start(queue: .main)
            receive()
        }

        func cancel() { connection.cancel() }

        func send(_ message: Message) {
            guard var data = try? JSONEncoder().encode(message) else { return }
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { _ in })
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data { self.buffer.append(data) }
                while let newline = self.buffer.firstIndex(of: 0x0A) {
                    let line = self.buffer[self.buffer.startIndex..<newline]
                    self.buffer.removeSubrange(self.buffer.startIndex...newline)
                    if let message = try? JSONDecoder().decode(Message.self, from: line) { self.onMessage?(message) }
                }
                if isComplete || error != nil {
                    self.connection.cancel()
                } else {
                    self.receive()
                }
            }
        }
    }
}
#endif

#if os(tvOS)
import Network

/// Apple TV tarafı: ağda kendini duyurur (Bonjour), gelen iPhone bağlantılarını kabul eder, söylenen adları iletir.
@Observable
final class VoiceHost {
    static let shared = VoiceHost()

    /// Bağlı iPhone sayısı (TV'de "iPhone bağlı" göstergesi için).
    private(set) var connectedCount = 0
    /// Son gelen ad ve olası diğer yazımları; her gelişte yeni kimlik alır, böylece aynı ad iki kez söylenince de işlenir.
    private(set) var incoming: (id: UUID, text: String, alternatives: [String])?
    /// Tahmin kutusunun işlediği son ad (işlenmediyse oyun bitmiştir).
    @ObservationIgnored var handledID: UUID?
    /// Telefondan son istek (ipucu, yeni oyun, pes et); her istekte yeni kimlik alır.
    private(set) var command: (id: UUID, kind: VoiceLink.Message.Kind, category: String?)?
    /// Telefona hangi kategorinin adlarını ipucu olarak vereceğini söylemek için.
    var category: String = "" { didSet { if category != oldValue { broadcast(hello) } } }
    /// Kalan ipucu sayısı; değişince telefondaki ampul düğmesi güncellenir.
    var hintsLeft = 0 { didSet { if hintsLeft != oldValue { broadcast(hello) } } }
    /// Oyun bitti mi; değişince telefondaki düğmeler güncellenir.
    var isOver = false { didSet { if isOver != oldValue { broadcast(hello) } } }

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var connections: [VoiceLink.Channel] = []

    private var hello: VoiceLink.Message { VoiceLink.Message(kind: .hello, category: category, hintsLeft: hintsLeft, over: isOver) }

    func start() {
        guard listener == nil, let l = try? NWListener(using: .tcp) else { return }
        // Ad verilmezse cihazın adı kullanılır ("Oturma Odası"); evde birden çok Apple TV varsa telefon hangisine bağlandığını gösterir.
        l.service = NWListener.Service(type: VoiceLink.bonjourType)
        l.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        // Ağ koparsa ya da dinleyici düşerse bir süre sonra yeniden kur.
        l.stateUpdateHandler = { [weak self] state in
            guard case .failed = state else { return }
            self?.listener?.cancel()
            self?.listener = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.start() }
        }
        l.start(queue: .main)
        listener = l
    }

    func reply(_ text: String) { broadcast(VoiceLink.Message(kind: .reply, text: text, hintsLeft: hintsLeft, over: isOver)) }

    private func broadcast(_ message: VoiceLink.Message) {
        for c in connections where c.isReady { c.send(message) }
    }

    private func accept(_ connection: NWConnection) {
        let channel = VoiceLink.Channel(connection)
        channel.onReady = { [weak self, weak channel] in
            guard let self, let channel else { return }
            self.connectedCount = self.connections.filter(\.isReady).count
            channel.send(self.hello)
        }
        channel.onClose = { [weak self, weak channel] in
            guard let self else { return }
            self.connections.removeAll { $0 === channel }
            self.connectedCount = self.connections.filter(\.isReady).count
        }
        channel.onMessage = { [weak self] message in
            switch message.kind {
            case .guess:
                guard let text = message.text else { return }
                self?.incoming = (UUID(), text, message.alternatives ?? [])
            case .hint, .newGame, .giveUp, .setCategory:
                self?.command = (UUID(), message.kind, message.category)
            case .hello, .reply:
                break
            }
        }
        connections.append(channel)
        channel.start()
    }
}
#endif

#if os(iOS)
import AVFoundation
import Speech

/// iPhone tarafı: Apple TV'yi bulup bağlanır, basılı tutulduğu sürece dinler, bırakınca adı gönderir.
///
/// Kısa, tek kelimelik yer adları genel konuşma tanımaya zor gelir. Bu yüzden ses aynı anda iki
/// tanıyıcıya verilir: Apple'ın sunucusundaki genel tanıyıcı (yer adları ipucu olarak) ve cihazda,
/// yalnızca o kategorinin yer adlarıyla eğitilmiş özel bir dil modeli (iOS 17+, dil destekliyorsa).
/// İkisinin bütün olası yazımları ve ara sonuçları TV'ye gider; TV bir yere uyan ilkini seçer.
@Observable
final class VoiceRemote {
    enum Connection: Equatable { case searching, connecting, connected }
    enum Listening: Equatable { case idle, listening, denied, unavailable }

    private(set) var connection: Connection = .searching
    private(set) var listening: Listening = .idle
    /// Dinlerken anlık yazıya dökülen metin.
    private(set) var transcript = ""
    /// TV'nin son yanıtı.
    private(set) var reply: String?
    /// TV'deki kategori (tanımaya ipucu olacak adlar bundan seçilir).
    private(set) var tvCategory: GameCategory?
    /// TV'deki oyunda kalan ipucu sayısı.
    private(set) var hintsLeft = 0
    /// TV'deki oyun bitti mi.
    private(set) var tvOver = false
    /// Bağlanılan Apple TV'nin adı.
    private(set) var tvName: String?

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var channel: VoiceLink.Channel?
    /// Bulunan son Apple TV adresi (bağlantı koparsa yeniden denemek için).
    @ObservationIgnored private var found: NWEndpoint?
    @ObservationIgnored private let audio = AVAudioEngine()
    /// Etkin tanıma işleri: sunucudaki genel tanıyıcı ve (hazırsa) cihazdaki özel model.
    @ObservationIgnored private var jobs: [Job] = []
    @ObservationIgnored private var sendWhenFinal = false
    /// Düğme hâlâ basılı mı (izin istenirken bırakılırsa dinleme hiç başlamasın).
    @ObservationIgnored private var holding = false
    /// Bu basışta görülen bütün ara yazımlar (bazen ara sonuç doğru, son sonuç yanlış oluyor).
    @ObservationIgnored private var partials: [String] = []
    /// Cihazdaki özel dil modeli, hangi kategori ve dil için hazırlandığıyla.
    @ObservationIgnored private var customModel: (key: String, config: SFSpeechLanguageModel.Configuration)?
    @ObservationIgnored private var preparingKey: String?

    private final class Job {
        let request: SFSpeechAudioBufferRecognitionRequest
        let custom: Bool
        var task: SFSpeechRecognitionTask?
        var best = ""
        var alternatives: [String] = []
        var done = false
        init(request: SFSpeechAudioBufferRecognitionRequest, custom: Bool) { self.request = request; self.custom = custom }
    }

    func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: VoiceLink.bonjourType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var endpoints = results.map(\.endpoint)
            #if DEBUG
            // Geliştirme: ATLAS_VOICE_TV="Atlas TV" yalnızca adında bu geçen TV'ye bağlanır (simülatör testi gerçek TV'ye gitmesin).
            if let only = ProcessInfo.processInfo.environment["ATLAS_VOICE_TV"] {
                endpoints = endpoints.filter { Self.name(of: $0)?.contains(only) == true }
            }
            #endif
            // Bağlı olunan TV hâlâ görünüyorsa onda kal.
            if let found = self.found, endpoints.contains(found) { return }
            self.found = endpoints.sorted { (Self.name(of: $0) ?? "") < (Self.name(of: $1) ?? "") }.first
            if self.channel == nil { self.connect() }
        }
        b.start(queue: .main)
        browser = b
    }

    private static func name(of endpoint: NWEndpoint) -> String? {
        if case .service(let name, _, _, _) = endpoint { return name }
        return nil
    }

    func stop() {
        browser?.cancel()
        browser = nil
        found = nil
        let c = channel
        channel = nil
        c?.cancel()
        connection = .searching
        cancelListening()
    }

    private func connect() {
        guard let found, browser != nil else { return }
        connection = .connecting
        tvName = Self.name(of: found)
        let c = VoiceLink.Channel(NWConnection(to: found, using: .tcp))
        c.onReady = { [weak self] in self?.connection = .connected }
        c.onClose = { [weak self, weak c] in
            guard let self, self.channel === c else { return }
            self.channel = nil
            self.connection = .searching
            // TV hâlâ görünüyorsa kısa süre sonra yeniden bağlan.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if self.channel == nil { self.connect() } }
        }
        c.onMessage = { [weak self] message in
            guard let self else { return }
            switch message.kind {
            case .hello:
                self.tvCategory = message.category.flatMap(GameCategory.init(rawValue:))
                self.prepareCustomModel()
            case .reply: self.reply = message.text
            case .guess, .hint, .newGame, .giveUp, .setCategory: break
            }
            if let n = message.hintsLeft { self.hintsLeft = n }
            if let over = message.over {
                // Yeni oyun başlayınca önceki oyunun yanıtı silinir.
                if self.tvOver && !over { self.reply = nil; self.transcript = "" }
                self.tvOver = over
            }
        }
        channel = c
        c.start()
    }

    // MARK: TV'deki oyunu yönetme

    /// Ampul: TV'de sıradaki ipucunu açar.
    func requestHint() { send(VoiceLink.Message(kind: .hint)) }
    /// Oyun bittiyse TV'de yeni oyun başlatır.
    func requestNewGame() { send(VoiceLink.Message(kind: .newGame)) }
    /// TV'deki oyunda pes eder.
    func requestGiveUp() { send(VoiceLink.Message(kind: .giveUp)) }
    /// TV'de kategoriyi değiştirir (telefondaki Atlas'ın kategorisi TV'yi etkilemez).
    func requestCategory(_ category: GameCategory) {
        tvCategory = category
        send(VoiceLink.Message(kind: .setCategory, category: category.rawValue))
    }

    // MARK: Özel dil modeli

    /// Tanımaya ipucu olacak adlar: seçili dildeki ve Türkçe adlar.
    private var placeNames: [String] {
        guard let tvCategory else { return [] }
        let places = PlaceSet.forCategory(tvCategory).places
        return Array(Set(places.map(\.name) + places.map(\.trName))).sorted()
    }

    /// TV'deki kategori için, yalnızca yer adlarından oluşan küçük bir dil modelini cihazda hazırlar
    /// (birkaç saniye sürer; hazır olana kadar yalnızca genel tanıyıcı kullanılır).
    private func prepareCustomModel() {
        guard let tvCategory else { return }
        let locale = L10n.shared.language.locale
        let key = "\(tvCategory.rawValue)-\(locale.identifier)"
        guard customModel?.key != key, preparingKey != key,
              let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else { return }
        preparingKey = key
        let names = placeNames
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("speech", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dataURL = dir.appendingPathComponent("\(key).bin")
        let config = SFSpeechLanguageModel.Configuration(languageModel: dir.appendingPathComponent("\(key).lm"),
                                                         vocabulary: dir.appendingPathComponent("\(key).vocab"))
        Task {
            do {
                let data = SFCustomLanguageModelData(locale: locale, identifier: "com.atanrikulu.atlas.places", version: "2")
                for name in names {
                    data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: name, count: 100))
                }
                try await data.export(to: dataURL)
                try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: dataURL, clientIdentifier: "com.atanrikulu.atlas",
                                                                          configuration: config)
                await MainActor.run {
                    if self.preparingKey == key { self.customModel = (key, config) }
                }
            } catch {
                await MainActor.run { if self.preparingKey == key { self.preparingKey = nil } }
            }
        }
    }

    // MARK: Dinleme

    /// İzinleri ister; basılı tutma başladığında çağrılır.
    func beginListening() {
        guard listening != .listening else { return }
        holding = true
        transcript = ""
        partials = []
        reply = nil
        // İzinler önceden verildiyse beklemeden başla; yoksa sözün başı kaçıyordu.
        if SFSpeechRecognizer.authorizationStatus() == .authorized, AVAudioApplication.shared.recordPermission == .granted {
            startRecognition()
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    guard status == .authorized, granted else { self.listening = .denied; return }
                    if self.holding { self.startRecognition() }
                }
            }
        }
    }

    /// Basılı tutma bitince: kayıt durur, son metin gelince TV'ye gönderilir.
    func endListening() {
        holding = false
        guard listening == .listening else { return }
        sendWhenFinal = true
        listening = .idle
        // Düğme çoğu zaman sözün son hecesi bitmeden bırakılır; kaydı biraz daha sürdür.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard self.sendWhenFinal, self.listening != .listening else { return }
            self.stopAudio()
            for job in self.jobs { job.request.endAudio() }
            // Tanıyıcılar son sonucu geciktirirse eldeki metinle gönder.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.finish() }
        }
    }

    private func stopAudio() {
        guard audio.isRunning else { return }
        audio.stop()
        audio.inputNode.removeTap(onBus: 0)
    }

    private func makeRequest(custom: Bool) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        request.addsPunctuation = false
        request.contextualStrings = placeNames
        if custom, let customModel {
            request.requiresOnDeviceRecognition = true
            request.customizedLanguageModel = customModel.config
        }
        return request
    }

    private func startRecognition() {
        let locale = L10n.shared.language.locale
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            listening = .unavailable
            return
        }
        // Önceki basıştan kalan kayıt varsa kapat (hızlı art arda basışlar).
        stopAudio()
        cancelJobs()
        jobs = [Job(request: makeRequest(custom: false), custom: false)]
        if customModel?.key == "\(tvCategory?.rawValue ?? "")-\(locale.identifier)" {
            jobs.append(Job(request: makeRequest(custom: true), custom: true))
        }
        let requests = jobs.map(\.request)
        do {
            let s = AVAudioSession.sharedInstance()
            // Varsayılan mod otomatik kazanç ve gürültü azaltma uygular (.measurement uzaktan konuşmada
            // sesi kısık bırakıyordu). Kayıt sırasında titreşim de kapanmasın.
            try s.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try s.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try s.setActive(true, options: .notifyOthersOnDeactivation)
            let input = audio.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                for r in requests { r.append(buffer) }
            }
            audio.prepare()
            try audio.start()
        } catch {
            listening = .unavailable
            return
        }
        sendWhenFinal = false
        listening = .listening
        for job in jobs {
            job.task = recognizer.recognitionTask(with: job.request) { [weak job] result, error in
                DispatchQueue.main.async {
                    guard let job, self.jobs.contains(where: { $0 === job }) else { return }
                    if let result {
                        job.best = result.bestTranscription.formattedString
                        job.alternatives = result.transcriptions.dropFirst().prefix(4).map(\.formattedString)
                        if !job.best.isEmpty, !self.partials.contains(job.best) { self.partials.append(job.best) }
                        self.transcript = self.primaryText
                    }
                    if result?.isFinal == true || error != nil {
                        job.done = true
                        if self.jobs.allSatisfy(\.done) { self.finish() }
                    }
                }
            }
        }
    }

    /// Ekranda gösterilen ve TV'ye ilk sırada giden yazım: genel tanıyıcınınki, boşsa özel modelinki.
    private var primaryText: String {
        jobs.first(where: { !$0.custom && !$0.best.isEmpty })?.best ?? jobs.first(where: { !$0.best.isEmpty })?.best ?? ""
    }

    private func finish() {
        guard sendWhenFinal else { return }
        sendWhenFinal = false
        let text = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sıra: özel modelin sonucu, genel tanıyıcının diğer yazımları, özel modelin diğer yazımları, ara sonuçlar.
        var alternatives: [String] = []
        for candidate in jobs.filter(\.custom).map(\.best) + jobs.filter { !$0.custom }.flatMap(\.alternatives)
            + jobs.filter(\.custom).flatMap(\.alternatives) + partials.reversed()
        where !candidate.isEmpty && candidate != text && !alternatives.contains(candidate) {
            alternatives.append(candidate)
        }
        cancelJobs()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if text.isEmpty { transcript = "" }
        guard !text.isEmpty else { return }
        transcript = text
        send(VoiceLink.Message(kind: .guess, text: text, alternatives: Array(alternatives.prefix(12))))
    }

    private func cancelJobs() {
        for job in jobs { job.task?.cancel() }
        jobs = []
    }

    private func cancelListening() {
        sendWhenFinal = false
        stopAudio()
        cancelJobs()
        if listening == .listening { listening = .idle }
    }

    private func send(_ message: VoiceLink.Message) {
        guard let channel, channel.isReady else { return }
        channel.send(message)
    }

    #if DEBUG
    /// Geliştirme: simülatörde mikrofonsuz denemek için metni doğrudan gönderir ("|" yerine "/" ile alternatifler).
    func debugSend(_ text: String) {
        let parts = text.split(separator: "/").map(String.init)
        send(VoiceLink.Message(kind: .guess, text: parts.first ?? text, alternatives: Array(parts.dropFirst())))
    }
    #endif
}
#endif
