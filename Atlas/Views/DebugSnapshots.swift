#if DEBUG && os(macOS)
import SwiftUI

/// Geliştirme aracı: `Atlas -renderSnapshots <klasör>` her kategorinin haritasını
/// birkaç örnek tahminle PNG olarak çizer ve uygulamayı kapatır. Kayıtlı oyun verisine dokunmaz.
enum DebugSnapshots {
    @MainActor
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-renderSnapshots"), args.indices.contains(i + 1) else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        let savedCategory = UserDefaults.standard.object(forKey: "category")

        for category in GameCategory.allCases {
            let game = GameModel()
            game.switchCategory(category)
            if game.mode == .daily { game.switchMode(.practice) }
            // Gizli yere en yakından uzağa birkaç tahmin; renk skalası görünsün diye.
            let others = game.places.places.filter { $0 != game.answer }
                .sorted { game.places.distance($0, game.answer) < game.places.distance($1, game.answer) }
            for idx in [0, others.count / 8, others.count / 3, others.count - 1] { game.submit(others[idx]) }
            game.highlighted = others[others.count / 3]

            let view = MapView(game: game).frame(width: 900, height: 600)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("map-\(category.rawValue).png"))
            }

            // Kenar çubuğuyla birlikte tam pencere (araç çubuğu ImageRenderer'da çizilmez).
            let full = ContentView(game: game, showStats: .constant(false), showHelp: .constant(false))
                .frame(width: 1180, height: 720)
            let fullRenderer = ImageRenderer(content: full)
            fullRenderer.scale = 1
            if let image = fullRenderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("window-\(category.rawValue).png"))
            }
        }

        // Kamera odak kadrajları: tahmin sonrası yakınlaşmanın son hâli.
        let focusCases: [(GameCategory, String)] = [(.world, "GRL"), (.world, "NOR"), (.world, "ISL"), (.world, "FRA"),
                                                    (.world, "RUS"), (.europe, "NOR"), (.europe, "DEU"), (.world, "USA")]
        for (category, code) in focusCases {
            let game = GameModel()
            game.switchCategory(category)
            if game.mode == .daily { game.switchMode(.practice) }
            guard let place = game.places.places.first(where: { $0.code == code }) else { continue }
            game.submit(place)
            let size = CGSize(width: 1000, height: 500)
            let i = game.places.places.firstIndex(of: place)!
            let t = game.places.usesGlobe
                ? MapCamera.globeTarget(game.places.globeGeometry.places[i].focus)
                : MapCamera.focusTarget(for: game.places.geometry.focusRects[i], bounds: game.places.geometry.bounds,
                                        size: size, maxZoom: (category == .turkey ? 8 : 24) * 0.75, category: category)
            let view = MapLayer(game: game, zoom: t.zoom, a: t.a, b: t.b, pulses: [:],
                                hovered: .constant(nil), hoverPoint: .constant(.zero))
                .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 0.5
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("focus-\(category.rawValue)-\(code).png"))
            }
        }

        // İstatistik bölümleri (kayıtlı veriyi yalnızca okur).
        for (mode, name) in [(GameMode.daily, "daily"), (.practice, "practice")] {
            let stats = Stats.load(key: Stats.key(category: .turkey, mode: mode))
            let view = VStack(alignment: .leading, spacing: 16) {
                CalendarSection(stats: stats, mode: mode)
                DiscoverySection(category: .turkey)
            }
            .padding(24)
            .frame(width: 520)
            .background(Color.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("stats-turkey-\(name).png"))
            }
        }

        // Marka: logo işareti, seviye pini, seviye kartı (ImageRenderer animasyonları oynatmaz).
        let brand = VStack(spacing: 20) {
            HStack(spacing: 20) {
                AtlasMark().frame(width: 96, height: 96)
                Text("Atlas").font(Brand.wordmark(84)).foregroundStyle(Brand.navy)
                LevelPin(level: 12).frame(width: 120, height: 120)
            }
            LevelCard(progress: LevelProgress(xp: 18_450))
            LevelCard(progress: LevelProgress(xp: 300),
                      reward: Reward(before: LevelProgress(xp: 120), after: LevelProgress(xp: 300)))
        }
        .padding(24)
        .frame(width: 520)
        .background(Brand.cream)
        let brandRenderer = ImageRenderer(content: brand)
        brandRenderer.scale = 1
        if let image = brandRenderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("brand.png"))
        }

        if let savedCategory { UserDefaults.standard.set(savedCategory, forKey: "category") }
        else { UserDefaults.standard.removeObject(forKey: "category") }
        exit(0)
    }
}
#endif
