import Foundation
import Observation

/// Arayüz dilleri. Çeviriler strings.json'da (web sürümüyle ortak dosya).
enum AppLanguage: String, CaseIterable, Identifiable {
    case tr, en, de, fr, es, it

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .tr: "🇹🇷"
        case .en: "🇬🇧"
        case .de: "🇩🇪"
        case .fr: "🇫🇷"
        case .es: "🇪🇸"
        case .it: "🇮🇹"
        }
    }

    var locale: Locale {
        switch self {
        case .tr: Locale(identifier: "tr_TR")
        case .en: Locale(identifier: "en_GB")
        case .de: Locale(identifier: "de_DE")
        case .fr: Locale(identifier: "fr_FR")
        case .es: Locale(identifier: "es_ES")
        case .it: Locale(identifier: "it_IT")
        }
    }

    /// Dilin kendi dilindeki adı ("Deutsch", "Français"…).
    var nativeName: String { L10n.table["lang.name"]?[rawValue] ?? rawValue }

    /// Ülke kodu (ISO 3166) → dil. Listede olmayan bölgeler cihaz diline, o da yoksa İngilizceye düşer.
    private static let regionLanguage: [String: AppLanguage] = {
        var map: [String: AppLanguage] = ["TR": .tr]
        for r in ["DE", "AT", "CH", "LI"] { map[r] = .de }
        for r in ["FR", "BE", "LU", "MC", "SN", "CI", "ML", "BF", "NE", "TG", "BJ", "CM", "GA", "CG", "CD", "MG",
                  "HT", "GN", "TD", "CF", "DJ", "RE"] { map[r] = .fr }
        for r in ["ES", "MX", "AR", "CO", "CL", "PE", "VE", "EC", "GT", "CU", "BO", "DO", "HN", "PY", "SV", "NI",
                  "CR", "PA", "UY", "PR", "GQ"] { map[r] = .es }
        for r in ["IT", "SM", "VA"] { map[r] = .it }
        return map
    }()

    /// Cihazın bölge ayarına göre; bölge listede yoksa cihazın tercih ettiği dillere göre.
    static var detected: AppLanguage {
        if let region = Locale.current.region?.identifier, let lang = regionLanguage[region] { return lang }
        for id in Locale.preferredLanguages {
            if let lang = AppLanguage(rawValue: String(id.prefix(2)).lowercased()) { return lang }
        }
        return .en
    }
}

/// Seçili dil. Elle seçilmemişse cihazın bölgesine göre belirlenir.
@Observable
final class L10n {
    static let shared = L10n()
    private static let key = "language"

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    private init() {
        language = UserDefaults.standard.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .detected
    }

    /// anahtar → dil kodu → metin
    static let table: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { fatalError("strings.json yüklenemedi") }
        return table
    }()
}

/// Çeviri; {ad} yer tutucuları doldurulur. n == 1 ise varsa ".one" biçimi kullanılır.
func L(_ key: String, _ vars: [String: CustomStringConvertible] = [:]) -> String {
    let lang = L10n.shared.language.rawValue
    var entry = L10n.table[key]
    if let n = vars["n"] as? Int, n == 1, let one = L10n.table["\(key).one"] { entry = one }
    var s = entry?[lang] ?? entry?["tr"] ?? key
    for (k, v) in vars { s = s.replacingOccurrences(of: "{\(k)}", with: v.description) }
    return s
}
