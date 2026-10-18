import CoreGraphics
import Foundation

/// Oyunda tahmin edilebilen bir yer: Türkiye'de bir il ya da dünyada bir ülke.
struct Place: Identifiable, Hashable {
    /// Kategori içinde benzersiz kimlik. İllerde plaka kodu, ülkelerde world.json sırası.
    let id: Int
    /// İllerde "06", ülkelerde "DEU" gibi kısa kod.
    let code: String
    /// Türkçe ad; sıralama ve kayıtlar bunu kullanır.
    let trName: String
    /// Diğer dillerdeki adlar (yalnızca ülkelerde; iller her dilde aynı).
    let names: [String: String]
    /// Her halka [boylam, enlem] çiftlerinden oluşan kapalı bir çokgendir.
    let rings: [[[Double]]]
    /// Aramada kabul edilen normalize edilmiş adlar: her dildeki ad ve takma adlar.
    let searchKeys: [String]

    init(id: Int, code: String, name: String, names: [String: String] = [:], aliases: [String], rings: [[[Double]]]) {
        self.id = id
        self.code = code
        trName = name
        self.names = names
        self.rings = rings
        var seen = Set<String>()
        searchKeys = ([name] + names.values.sorted() + aliases).map(TurkishText.normalize).filter { seen.insert($0).inserted }
    }

    /// Seçili dildeki ad.
    var name: String {
        let lang = L10n.shared.language
        return lang == .tr ? trName : names[lang.rawValue] ?? trName
    }

    static func == (lhs: Place, rhs: Place) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum GameCategory: String, CaseIterable, Identifiable {
    case turkey, europe, asia, africa, northAmerica, southAmerica, oceania, world

    var id: String { rawValue }

    var title: String { L("cat.\(rawValue)") }

    var symbol: String {
        switch self {
        case .turkey: "map"
        case .europe, .africa: "globe.europe.africa"
        case .asia, .oceania: "globe.asia.australia"
        case .northAmerica, .southAmerica: "globe.americas"
        case .world: "globe"
        }
    }

    /// Metin anahtarlarında kullanılır: "province" (il) ya da "country" (ülke).
    var kind: String { self == .turkey ? "province" : "country" }

    var subtitle: String {
        let count = PlaceSet.forCategory(self).places.count
        switch self {
        case .turkey, .world: return L("subtitle.\(rawValue)", ["n": count])
        default: return L("subtitle.continent", ["n": count, "continent": title])
        }
    }
}

/// Bir kategorinin yerleri, aralarındaki mesafeler ve harita görünümü.
final class PlaceSet {
    let category: GameCategory
    /// Ada göre sıralı.
    let places: [Place]
    let maxDistance: Int
    /// Oyunda olmayan, yalnızca bağlam için soluk çizilen komşu topraklar.
    let background: [[[[Double]]]]
    /// Haritada gösterilecek alan (boylam/enlem). nil ise yerlerin tamamına sığdırılır.
    let viewBounds: CGRect?
    /// Antimeridyeni aşan bölgelerde boylamı kaydırır (örn. Okyanusya'da -170° → 190°).
    let shiftLongitude: (Double) -> Double

    private let byID: [Int: Place]
    private let distanceLookup: (Int, Int) -> Int
    private let extraAliases: [String: Int]

    private init(category: GameCategory, places: [Place], background: [[[[Double]]]], viewBounds: CGRect?,
                 shiftLongitude: @escaping (Double) -> Double = { $0 }, extraAliases: [String: Int] = [:],
                 distance: @escaping (Int, Int) -> Int) {
        self.category = category
        self.places = places.sorted { $0.trName.compare($1.trName, locale: Locale(identifier: "tr_TR")) == .orderedAscending }
        self.background = background
        self.viewBounds = viewBounds
        self.shiftLongitude = shiftLongitude
        self.extraAliases = extraAliases
        byID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        distanceLookup = distance
        var maxD = 1
        for a in places { for b in places where a.id < b.id { maxD = max(maxD, distance(a.id, b.id)) } }
        maxDistance = maxD
    }

    // MARK: - Sorgular

    func place(id: Int) -> Place? { byID[id] }

    func distance(_ a: Place, _ b: Place) -> Int {
        a == b ? 0 : distanceLookup(a.id, b.id)
    }

    /// Yazılan metne tam uyan yeri bulur (büyük/küçük harf, boşluk ve Türkçe karakter farkı gözetmez).
    func match(_ text: String) -> Place? {
        let key = TurkishText.normalize(text)
        guard !key.isEmpty else { return nil }
        if let exact = places.first(where: { $0.searchKeys.contains(key) }) { return exact }
        if category == .turkey, let plate = Int(key) { return place(id: plate) }
        return extraAliases[key].flatMap(place(id:))
    }

    func suggestions(for text: String, limit: Int = 6) -> [Place] {
        let key = TurkishText.normalize(text)
        guard !key.isEmpty else { return [] }
        // Önce seçili dildeki adı yazılanla başlayanlar, sonra diğer ad ve takma adlar, en son adın içinde geçenler.
        let locale = L10n.shared.language.locale
        let named = places.map { ($0, TurkishText.normalize($0.name)) }
        func sorted(_ list: [Place]) -> [Place] {
            list.sorted { $0.name.compare($1.name, locale: locale) == .orderedAscending }
        }
        let primary = sorted(named.filter { $0.1.hasPrefix(key) }.map(\.0))
        let alias = sorted(places.filter { p in !primary.contains(p) && p.searchKeys.contains { $0.hasPrefix(key) } })
        let contains = sorted(named.filter { p, k in !primary.contains(p) && !alias.contains(p) && k.contains(key) }.map(\.0))
        return Array((primary + alias + contains).prefix(limit))
    }

    // MARK: - Harita geometrisi

    private var cachedGeometry: MapGeometry?
    /// Düz harita projeksiyonu (Dünya için de keşif haritasında kullanılır).
    var geometry: MapGeometry {
        if let cachedGeometry { return cachedGeometry }
        let g = MapGeometry(set: self)
        cachedGeometry = g
        return g
    }

    private var cachedGlobe: GlobeGeometry?
    /// Küre geometrisi (Dünya kategorisi).
    var globeGeometry: GlobeGeometry {
        if let cachedGlobe { return cachedGlobe }
        let g = GlobeGeometry(set: self)
        cachedGlobe = g
        return g
    }

    /// Haritası 3D küre olarak çizilen kategori.
    var usesGlobe: Bool { category == .world }

    // MARK: - Yükleme

    private static var cache: [GameCategory: PlaceSet] = [:]

    static func forCategory(_ category: GameCategory) -> PlaceSet {
        if let set = cache[category] { return set }
        let set = category == .turkey ? makeTurkey() : makeWorld(category)
        cache[category] = set
        return set
    }

    private static func makeTurkey() -> PlaceSet {
        struct Raw: Decodable { let id: Int; let name: String; let rings: [[[Double]]] }
        struct Payload: Decodable { let provinces: [Raw]; let distances: [[Int]] }
        let payload: Payload = loadJSON("provinces")
        let places = payload.provinces.map {
            Place(id: $0.id, code: String(format: "%02d", $0.id), name: $0.name, aliases: [], rings: $0.rings)
        }
        let world = WorldData.shared
        // Türkiye dışındaki ülkeler denizleri ve komşuları göstermek için arka planda çizilir.
        let background = world.countries.filter { $0.code != "TUR" }.map(\.rings) + world.background
        let d = payload.distances
        return PlaceSet(category: .turkey, places: places, background: background, viewBounds: nil,
                        extraAliases: ["afyon": 3, "maras": 46, "urfa": 63, "antep": 27, "icel": 33, "izmit": 41, "adapazari": 54],
                        distance: { d[$0 - 1][$1 - 1] })
    }

    private static func makeWorld(_ category: GameCategory) -> PlaceSet {
        let world = WorldData.shared
        let members = world.countries.filter { category == .world || $0.continents.contains(category.rawValue) }
        let memberCodes = Set(members.map(\.code))
        let places = members.map { Place(id: $0.id, code: $0.code, name: $0.name, names: $0.names, aliases: $0.aliases, rings: $0.rings) }
        let background = world.countries.filter { !memberCodes.contains($0.code) }.map(\.rings) + world.background

        // Görünüm alanları: minX = batı boylamı, minY = güney enlemi.
        let view: (CGRect, (Double) -> Double) = switch category {
        case .europe: (CGRect(x: -25, y: 34, width: 70, height: 38), { $0 })
        case .asia: (CGRect(x: 25, y: -11, width: 125, height: 67), { $0 })
        case .africa: (CGRect(x: -26, y: -36, width: 90, height: 74), { $0 })
        case .northAmerica: (CGRect(x: -170, y: 6, width: 160, height: 74), { $0 > 100 ? $0 - 360 : $0 })
        case .southAmerica: (CGRect(x: -93, y: -56, width: 62, height: 70), { $0 })
        case .oceania: (CGRect(x: 110, y: -48, width: 125, height: 70), { $0 < 0 ? $0 + 360 : $0 })
        default: (CGRect(x: -170, y: -57, width: 350, height: 140), { $0 })
        }
        let d = world.distances
        return PlaceSet(category: category, places: places, background: background, viewBounds: view.0,
                        shiftLongitude: view.1, distance: { d[$0 - 1][$1 - 1] })
    }
}

/// world.json: dünya ülkeleri, arka plan bölgeleri ve ülke çiftleri arası mesafeler.
final class WorldData {
    static let shared = WorldData()

    struct Country: Decodable {
        let id: Int
        let code: String
        let name: String
        let names: [String: String]
        let aliases: [String]
        let continents: [String]
        let rings: [[[Double]]]
    }

    private struct Payload: Decodable {
        let countries: [Country]
        let background: [[[[Double]]]]
        let distances: [[Int]]
    }

    let countries: [Country]
    let background: [[[[Double]]]]
    let distances: [[Int]]

    private init() {
        let payload: Payload = loadJSON("world")
        countries = payload.countries
        background = payload.background
        distances = payload.distances
    }
}

private func loadJSON<T: Decodable>(_ name: String) -> T {
    guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let value = try? JSONDecoder().decode(T.self, from: data)
    else { fatalError("\(name).json yüklenemedi") }
    return value
}
