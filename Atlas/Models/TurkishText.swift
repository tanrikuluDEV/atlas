import Foundation

enum TurkishText {
    private static let turkish = Locale(identifier: "tr_TR")

    /// "İstanbul", "istanbul", "ISTANBUL" → "istanbul"; "Bosna-Hersek" → "bosnahersek".
    /// Türkçe harfler ASCII karşılıklarına indirgenir, boşluk ve noktalama atılır.
    static func normalize(_ text: String) -> String {
        let folded = text.lowercased(with: turkish)
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: turkish)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func formatKm(_ km: Int) -> String {
        let f = NumberFormatter()
        f.locale = L10n.shared.language.locale
        f.numberStyle = .decimal
        return "\(f.string(from: NSNumber(value: km)) ?? "\(km)") km"
    }
}
