import Foundation

/// Her il ve ülke için 6 dilde 3 genel kültür ipucu (hints.json, web'le ortak).
/// İlk ipucu en genel, sonuncusu en belirgin olandır. İller plaka koduyla, ülkeler ISO koduyla anılır.
enum Hints {
    private struct File: Decodable {
        let provinces: [String: [String: [String]]]
        let countries: [String: [String: [String]]]
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "hints", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    static func hints(for place: Place, in category: GameCategory) -> [String] {
        let entry = category == .turkey ? file?.provinces[String(place.id)] : file?.countries[place.code]
        return entry?[L10n.shared.language.rawValue] ?? entry?["tr"] ?? []
    }
}
