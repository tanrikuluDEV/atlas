import SwiftUI

/// Kamera: düz haritada (a, b) harita merkezi; kürede (a, b) merkezdeki boylam/enlem.
struct Camera: Equatable {
    var zoom: CGFloat
    var a: Double
    var b: Double
}

/// Yeni tahminde kısa parlama ya da bulunan yerde yeşil nabız.
struct Pulse: Equatable {
    let start: Date
    let duration: Double
    let win: Bool
}

/// Kategori haritası. Tahmin edilen yerler gizli yere uzaklıklarına göre renklenir.
/// Dünya kategorisi 3D küre olarak çizilir. Her tahminde kamera yerin ve çevresinin üzerine uçar.
struct MapView: View {
    let game: GameModel

    @State private var cam: Camera?
    @State private var committed: Camera?
    @State private var viewSize: CGSize = .zero
    /// Yeni bir uçuş başladığında eskisinin ikinci aşaması iptal edilsin diye.
    @State private var flightID = 0
    @State private var hovered: Place?
    @State private var hoverPoint: CGPoint = .zero
    @State private var pulses: [Int: Pulse] = [:]
    #if os(tvOS)
    @FocusState private var mapFocused: Bool
    #endif

    private var places: PlaceSet { game.places }
    private var home: Camera { MapCamera.home(for: places) }
    private var current: Camera { cam ?? home }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                MapLayer(game: game, zoom: current.zoom, a: current.a, b: current.b, pulses: pulses,
                         hovered: $hovered, hoverPoint: $hoverPoint)
                    .contentShape(Rectangle())
                    #if os(tvOS)
                    // Kumanda: harita odaktayken yön tuşları kaydırır (kürede döndürür), ⏯ baştan gösterir.
                    .focusable()
                    .focused($mapFocused)
                    .onMoveCommand { pan($0) }
                    .onPlayPauseCommand { resetView() }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(mapFocused ? Color.white.opacity(0.8) : .clear, lineWidth: 4)
                    }
                    #else
                    .gesture(dragGesture(size: geo.size))
                    .simultaneousGesture(magnifyGesture)
                    .onTapGesture(count: 2) { resetView() }
                    #endif

                #if os(tvOS)
                // TV'de harita ekran kenarına kadar uzanır; lejant ve düğmeler güvenli alanın içinde kalsın.
                LegendView(places: places)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 80)
                    .padding(.bottom, 60)

                zoomControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 24)
                    .padding(.bottom, 60)
                #else
                LegendView(places: places)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(Platform.isMac ? 12 : 8)

                zoomControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
                #endif
            }
            .clipped()
            .onAppear {
                viewSize = geo.size
                // Açılışta bitmiş bir günlük bulmaca varsa gizli yer odakta olsun.
                if game.isOver { DispatchQueue.main.async { showRoundStart() } }
            }
            .onChange(of: geo.size) { viewSize = geo.size }
        }
        .onChange(of: game.category) {
            // Farklı bir harita: kamerayı animasyonsuz baştan kur.
            flightID += 1
            hovered = nil
            pulses = [:]
            cam = nil
            committed = nil
            DispatchQueue.main.async { showRoundStart() }
        }
        .onChange(of: game.answer) { showRoundStart() }
        .onChange(of: game.lastGuess) { _, guess in
            guard let guess else { return }
            focus(on: guess.place)
            if game.status == .won {
                startPulse(game.answer, duration: 2.6, win: true)
            } else {
                startPulse(guess.place, duration: 1.3, win: false)
            }
        }
        .onChange(of: game.highlighted) { _, place in
            if let place { focus(on: place) }
        }
        .onChange(of: game.status) { old, new in
            // Pes edilince gizli yer de gösterilsin.
            if old == .playing && new == .lost { focus(on: game.answer) }
        }
    }

    /// Yeni tura geçince: bitmiş bir oyuna dönüldüyse (ör. çözülmüş günlük bulmaca) gizli yere odaklan,
    /// değilse tüm haritayı göster.
    private func showRoundStart() {
        if game.isOver { focus(on: game.answer) } else { resetView() }
    }

    // MARK: - Animasyonlar

    private func startPulse(_ place: Place, duration: Double, win: Bool) {
        let pulse = Pulse(start: .now, duration: duration, win: win)
        pulses[place.id] = pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
            if pulses[place.id] == pulse { pulses[place.id] = nil }
        }
    }

    // MARK: - Kamera uçuşu

    private var maxZoom: CGFloat { places.usesGlobe ? 12 : (game.category == .turkey ? 8 : 24) }

    /// Yeri ve çevresini gösterecek kadar yumuşakça yakınlaşır; aşırı yakına inmez.
    private func focus(on place: Place) {
        guard viewSize.width > 0, let i = places.places.firstIndex(of: place) else { return }
        let target = places.usesGlobe
            ? MapCamera.globeTarget(places.globeGeometry.places[i].focus)
            : MapCamera.focusTarget(for: places.geometry.focusRects[i], bounds: places.geometry.bounds,
                                    size: viewSize, maxZoom: maxZoom * 0.75, category: game.category)
        fly(to: target)
    }

    private func fly(to target: Camera) {
        flightID += 1
        let id = flightID
        let from = current
        var to = target

        let farAway: Bool
        var mid: Camera
        if places.usesGlobe {
            // Kısa yoldan dön: hedef boylamı mevcut boylama en yakın eşdeğere taşı.
            to.a = from.a + MapCamera.wrapLon(to.a - from.a)
            farAway = MapCamera.angularDistance(from, to) > 35
            mid = Camera(zoom: min(from.zoom, to.zoom, 1.15), a: (from.a + to.a) / 2, b: (from.b + to.b) / 2)
        } else {
            let fit = MapCamera.fit(size: viewSize, bounds: places.geometry.bounds)
            let screenDistance = hypot(to.a - from.a, to.b - from.b) * fit * from.zoom
            farAway = screenDistance > max(viewSize.width, viewSize.height) * 0.8
            // Uzak bir yere geçerken önce iki yeri birlikte gösterecek kadar uzaklaş.
            let spanX = abs(to.a - from.a) * 1.3 + viewSize.width / (fit * to.zoom)
            let spanY = abs(to.b - from.b) * 1.3 + viewSize.height / (fit * to.zoom)
            let midZoom = max(1, min(from.zoom, to.zoom, viewSize.width / (fit * spanX), viewSize.height / (fit * spanY)))
            mid = Camera(zoom: midZoom, a: (from.a + to.a) / 2, b: (from.b + to.b) / 2)
        }
        committed = to

        guard farAway else {
            withAnimation(.easeInOut(duration: places.usesGlobe ? 0.8 : 0.75)) { cam = to }
            return
        }
        withAnimation(.easeIn(duration: places.usesGlobe ? 0.55 : 0.45)) {
            cam = mid
        } completion: {
            guard id == flightID else { return }
            withAnimation(.easeOut(duration: places.usesGlobe ? 0.65 : 0.6)) { cam = to }
        }
    }

    private func resetView() {
        flightID += 1
        var target = home
        if places.usesGlobe { target.a = current.a + MapCamera.wrapLon(target.a - current.a) }
        committed = target
        withAnimation(.easeInOut(duration: 0.55)) { cam = target }
    }

    // MARK: - Hareketler

    #if os(tvOS)
    /// Kumandanın yön tuşları: düz haritada görünümün beşte biri kadar kaydırır, kürede döndürür.
    private func pan(_ direction: MoveCommandDirection) {
        let (dx, dy): (Double, Double) = switch direction {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .up: (0, -1)
        case .down: (0, 1)
        @unknown default: (0, 0)
        }
        flightID += 1
        var target = committed ?? current
        if places.usesGlobe {
            let step = 20 / Double(current.zoom)
            target.a += dx * step
            target.b = max(-80, min(80, target.b - dy * step))
        } else {
            let scale = MapCamera.fit(size: viewSize, bounds: places.geometry.bounds) * current.zoom
            target.a += dx * viewSize.width * 0.2 / scale
            target.b += dy * viewSize.height * 0.2 / scale
        }
        committed = target
        withAnimation(.easeInOut(duration: 0.3)) { cam = target }
    }
    #else
    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                flightID += 1
                let base = committed ?? current
                if places.usesGlobe {
                    // Kürede sürükleme döndürür.
                    let r = (min(size.width, size.height) / 2 - MapCamera.padding) * current.zoom
                    let k = 180 / (.pi * max(r, 1))
                    cam = Camera(zoom: current.zoom, a: base.a - v.translation.width * k,
                                 b: max(-80, min(80, base.b + v.translation.height * k)))
                } else {
                    let scale = MapCamera.fit(size: size, bounds: places.geometry.bounds) * current.zoom
                    cam = Camera(zoom: current.zoom, a: base.a - v.translation.width / scale,
                                 b: base.b - v.translation.height / scale)
                }
            }
            .onEnded { _ in committed = cam }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                flightID += 1
                let base = committed ?? current
                cam = Camera(zoom: clampZoom(base.zoom * v.magnification), a: current.a, b: current.b)
            }
            .onEnded { _ in committed = cam }
    }
    #endif

    private func clampZoom(_ value: CGFloat) -> CGFloat { min(max(value, 1), maxZoom) }

    private func stepZoom(_ factor: CGFloat) {
        flightID += 1
        var target = current
        target.zoom = clampZoom(current.zoom * factor)
        committed = target
        withAnimation(.easeInOut(duration: 0.3)) { cam = target }
    }

    #if os(tvOS)
    private var zoomControls: some View {
        HStack(spacing: 16) {
            Button { stepZoom(1.5) } label: { Image(systemName: "plus") }
            Button { stepZoom(1 / 1.5) } label: { Image(systemName: "minus") }
            Button { resetView() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
        }
        .font(.callout)
    }
    #else
    private var zoomControls: some View {
        VStack(spacing: 0) {
            Button { stepZoom(1.5) } label: {
                Image(systemName: "plus").frame(width: 28, height: 28)
            }
            Divider().frame(width: 28)
            Button { stepZoom(1 / 1.5) } label: {
                Image(systemName: "minus").frame(width: 28, height: 28)
            }
            Divider().frame(width: 28)
            Button { resetView() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 28, height: 28)
            }
            .help(L("map.reset"))
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
    #endif
}

// MARK: - Kamera hesapları

enum MapCamera {
    static let padding: CGFloat = 20
    /// Küre: odaklanınca görünen açı (derece). İzlanda ekran görüntüsündeki ölçeğe göre.
    static let globeSpan: ClosedRange<Double> = 48...62
    /// Küre açılışta Türkiye tarafını gösterir.
    static let globeHome = (lon: 32.0, lat: 28.0)

    static func home(for set: PlaceSet) -> Camera {
        if set.usesGlobe { return Camera(zoom: 1, a: globeHome.lon, b: globeHome.lat) }
        let b = set.geometry.bounds
        return Camera(zoom: 1, a: b.midX, b: b.midY)
    }

    /// Odaklanırken gösterilecek alanın sınırları (haritanın genişliğine oranla).
    static func spanFractions(for category: GameCategory) -> (min: CGFloat, max: CGFloat) {
        switch category {
        case .turkey: (2 / 5, 0.55)
        case .world: (0.14, 0.18)
        default: (1 / 3, 0.5)
        }
    }

    /// Yakınlaştırma 1'deyken haritanın görünüme sığdığı ölçek.
    static func fit(size: CGSize, bounds: CGRect) -> CGFloat {
        max(min((size.width - padding * 2) / bounds.width, (size.height - padding * 2) / bounds.height), 0.01)
    }

    /// Düz harita: yerin ana toprağının ~5 katı genişlikte bir alan, `spanFractions` sınırları içinde.
    /// Kamera, görünen alan haritanın dışına fazla taşmayacak şekilde kaydırılır.
    static func focusTarget(for rect: CGRect, bounds: CGRect, size: CGSize, maxZoom: CGFloat,
                            category: GameCategory) -> Camera {
        let fit = fit(size: size, bounds: bounds)
        let fractions = spanFractions(for: category)
        let mapSpan = max(bounds.width, bounds.height)
        let span = min(max(max(rect.width, rect.height) * 5.2, mapSpan * fractions.min), mapSpan * fractions.max)
        var z = min((size.width - padding * 2) / (fit * span), (size.height - padding * 2) / (fit * span))
        if z <= 1.05 { return Camera(zoom: 1, a: bounds.midX, b: bounds.midY) }
        z = min(z, maxZoom)

        // Merkez kenardan en az görünen yarı boyutun %80'i kadar içeride kalır.
        let hw = size.width / 2 / (fit * z) * 0.8, hh = size.height / 2 / (fit * z) * 0.8
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat, _ mid: CGFloat) -> CGFloat {
            lo <= hi ? min(max(v, lo), hi) : mid
        }
        return Camera(zoom: z, a: clamp(rect.midX, bounds.minX + hw, bounds.maxX - hw, bounds.midX),
                      b: clamp(rect.midY, bounds.minY + hh, bounds.maxY - hh, bounds.midY))
    }

    /// Küre: ülkeyi ortaya getir, çevresiyle birlikte görünecek kadar yaklaş.
    static func globeTarget(_ focus: (lon: Double, lat: Double, size: Double)) -> Camera {
        let span = min(max(focus.size * 5.2, globeSpan.lowerBound), globeSpan.upperBound)
        // Yakınlaştırma z'de görünen yarı açı θ için sin θ = 1/z.
        let zoom = max(1, 1 / sin(span / 2 * .pi / 180))
        return Camera(zoom: zoom, a: focus.lon, b: max(-70, min(75, focus.lat)))
    }

    static func wrapLon(_ l: Double) -> Double {
        var x = (l + 180).truncatingRemainder(dividingBy: 360)
        if x < 0 { x += 360 }
        return x - 180
    }

    static func angularDistance(_ p: Camera, _ q: Camera) -> Double {
        let r = Double.pi / 180
        let c = sin(p.b * r) * sin(q.b * r) + cos(p.b * r) * cos(q.b * r) * cos((q.a - p.a) * r)
        return acos(max(-1, min(1, c))) / r
    }

    static func transform(size: CGSize, bounds: CGRect, cam: Camera) -> CGAffineTransform {
        let scale = fit(size: size, bounds: bounds) * cam.zoom
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                 tx: size.width / 2 - cam.a * scale, ty: size.height / 2 - cam.b * scale)
    }
}

// MARK: - Çizim katmanı

/// Haritanın çizimi. `Animatable` olduğu için kamera değerleri animasyon sırasında her karede
/// ara değerlerle yeniden çizilir; parlama animasyonları için TimelineView kullanılır.
struct MapLayer: View, Animatable {
    let game: GameModel
    var zoom: CGFloat
    var a: Double
    var b: Double
    let pulses: [Int: Pulse]
    @Binding var hovered: Place?
    @Binding var hoverPoint: CGPoint
    /// Dil değişince adlar yeniden çizilsin diye görünümün değerine katılır (Canvas gözlemlenmez).
    var language: AppLanguage = L10n.shared.language

    @AppStorage(AppSettings.showDistanceKey) private var showDistance = true
    @Environment(\.colorScheme) private var colorScheme

    /// Ekranda bu boyuttan küçük kalan yerler, görünür olsun diye bir noktayla işaretlenir.
    private let markerThreshold: CGFloat = 6
    private let markerRadius: CGFloat = 4 * Platform.drawScale

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<Double, Double>> {
        get { AnimatablePair(zoom, AnimatablePair(a, b)) }
        set {
            zoom = newValue.first
            a = newValue.second.first
            b = newValue.second.second
        }
    }

    private var places: PlaceSet { game.places }
    private var cam: Camera { Camera(zoom: zoom, a: a, b: b) }

    private struct LabelItem {
        let place: Place
        let point: CGPoint
    }

    var body: some View {
        TimelineView(.animation(paused: pulses.isEmpty)) { timeline in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        let labels = places.usesGlobe
                            ? drawGlobe(&ctx, size: size, now: timeline.date)
                            : drawFlat(&ctx, size: size, now: timeline.date)
                        drawLabels(&ctx, labels, size: size)
                    }
                    #if os(iOS)
                    // Dokunmatik ekranda fareyle üzerine gelme olmadığı için dokunulan yerin adı gösterilir.
                    .onTapGesture { point in
                        let tapped = place(at: point, size: geo.size)
                        hoverPoint = point
                        hovered = (tapped == hovered) ? nil : tapped
                    }
                    #endif
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            hoverPoint = point
                            hovered = place(at: point, size: geo.size)
                        case .ended:
                            hovered = nil
                        }
                    }

                    if let highlighted = game.highlighted, hovered != highlighted,
                       let anchor = highlightAnchor(size: geo.size) {
                        Text(highlighted.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ColorScale.highlight, in: Capsule())
                            .fixedSize()
                            .position(x: min(max(anchor.point.x, 70), geo.size.width - 70),
                                      y: max(anchor.point.y - (anchor.small ? 26 : 16), 16))
                            .allowsHitTesting(false)
                    }

                    if let hovered, let label = hoverLabel(for: hovered) {
                        Text(label)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .fixedSize()
                            // Sağ kenara yakınsa etiketi imlecin soluna al.
                            .offset(x: hoverPoint.x > geo.size.width - 190 ? hoverPoint.x - 190 : hoverPoint.x + 14,
                                    y: hoverPoint.y + 10)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: Düz harita

    private func drawFlat(_ ctx: inout GraphicsContext, size: CGSize, now: Date) -> [LabelItem] {
        let geometry = places.geometry
        let transform = MapCamera.transform(size: size, bounds: geometry.bounds, cam: cam)
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -20, dy: -20)

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.sea))
        for path in geometry.backgroundPaths where path.boundingRect.applying(transform).intersects(visible) {
            let shape = path.applying(transform)
            ctx.fill(shape, with: .color(palette.backgroundLand))
            ctx.stroke(shape, with: .color(palette.border.opacity(0.7)), lineWidth: 0.4)
        }

        var labels: [LabelItem] = []
        for (index, path) in geometry.paths.enumerated() where path.boundingRect.applying(transform).intersects(visible) {
            let place = places.places[index]
            let shape = path.applying(transform)
            let color = fill(for: place)
            let isHovered = hovered == place
            ctx.fill(shape, with: .color(color))
            ctx.stroke(shape, with: .color(isHovered ? .primary : palette.border), lineWidth: isHovered ? 1.6 : 0.6)
            let r = shape.boundingRect
            let small = r.width < markerThreshold && r.height < markerThreshold
            if small { drawMarker(&ctx, at: CGPoint(x: r.midX, y: r.midY), color: color, hovered: isHovered) }
            if let pulse = pulses[place.id] { strokePulse(&ctx, shape, pulse, now: now) }
            if showsLabel(place) {
                let p = small ? CGPoint(x: r.midX, y: r.midY - 10) : geometry.labelPoints[index].applying(transform)
                labels.append(LabelItem(place: place, point: p))
            }
        }

        // Listeden seçilen yer en üstte, parlak bir çerçeveyle çizilir.
        if let i = highlightIndex {
            let shape = geometry.paths[i].applying(transform)
            strokeHighlight(&ctx, shape, rect: shape.boundingRect)
        }
        return labels
    }

    // MARK: Küre

    private func drawGlobe(_ ctx: inout GraphicsContext, size: CGSize, now: Date) -> [LabelItem] {
        let globe = places.globeGeometry
        let proj = GlobeProjection(size: size, zoom: zoom, lon: a, lat: b)
        let c = proj.center, r = proj.radius
        let disk = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

        // Uzay, atmosfer parıltısı ve gölgeli okyanus
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.space))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.08, y: c.y - r * 1.08, width: r * 2.16, height: r * 2.16)),
                 with: .radialGradient(Gradient(colors: [palette.atmosphere, palette.atmosphere.opacity(0)]),
                                       center: c, startRadius: r * 0.98, endRadius: r * 1.08))
        ctx.fill(disk, with: .radialGradient(Gradient(colors: [palette.seaLight, palette.sea]),
                                             center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35),
                                             startRadius: r * 0.1, endRadius: r))

        var inner = ctx
        inner.clip(to: disk)
        drawGraticule(&inner, proj)

        for rings in globe.background {
            var path = Path()
            if proj.trace(rings, into: &path) {
                inner.fill(path, with: .color(palette.backgroundLand))
                inner.stroke(path, with: .color(palette.border.opacity(0.7)), lineWidth: 0.4)
            }
        }

        var labels: [LabelItem] = []
        let pxPerDeg = r * .pi / 180
        for (index, shape) in globe.places.enumerated() {
            var path = Path()
            guard proj.trace(shape.rings, into: &path) else { continue }
            let place = places.places[index]
            let color = fill(for: place)
            let isHovered = hovered == place
            inner.fill(path, with: .color(color))
            inner.stroke(path, with: .color(isHovered ? .primary : palette.border), lineWidth: isHovered ? 1.6 : 0.5)
            if let pulse = pulses[place.id] { strokePulse(&inner, path, pulse, now: now) }

            let lp = proj.project(lon: shape.label.lon, lat: shape.label.lat)
            let small = shape.angular * pxPerDeg < markerThreshold
            if small && lp.cosc > 0 { drawMarker(&inner, at: lp.point, color: color, hovered: isHovered) }
            if index == highlightIndex {
                strokeHighlight(&inner, path, rect: small ? CGRect(origin: lp.point, size: .zero) : path.boundingRect)
            }
            if lp.cosc > 0.2 && showsLabel(place) {
                labels.append(LabelItem(place: place, point: small ? CGPoint(x: lp.point.x, y: lp.point.y - 10) : lp.point))
            }
        }

        // Kenarda hafif gölge: küreye derinlik verir.
        ctx.fill(disk, with: .radialGradient(Gradient(colors: [.clear, palette.globeShade]),
                                             center: c, startRadius: r * 0.75, endRadius: r))
        return labels
    }

    private func drawGraticule(_ ctx: inout GraphicsContext, _ proj: GlobeProjection) {
        var path = Path()
        func line(_ pts: [(Double, Double)]) {
            var pen = false
            for (lon, lat) in pts {
                let p = proj.project(lon: lon, lat: lat)
                guard p.cosc > 0 else { pen = false; continue }
                if pen { path.addLine(to: p.point) } else { path.move(to: p.point); pen = true }
            }
        }
        for lon in stride(from: -180.0, to: 180, by: 30) {
            line(stride(from: -80.0, through: 80, by: 4).map { (lon, $0) })
        }
        for lat in stride(from: -60.0, through: 60, by: 30) {
            line(stride(from: -180.0, through: 180, by: 4).map { ($0, lat) })
        }
        ctx.stroke(path, with: .color(palette.graticule), lineWidth: 0.6)
    }

    // MARK: Ortak çizim parçaları

    private func drawMarker(_ ctx: inout GraphicsContext, at p: CGPoint, color: Color, hovered: Bool) {
        let marker = Path(ellipseIn: CGRect(x: p.x - markerRadius, y: p.y - markerRadius,
                                            width: markerRadius * 2, height: markerRadius * 2))
        ctx.fill(marker, with: .color(color))
        ctx.stroke(marker, with: .color(hovered ? .primary : palette.markerStroke), lineWidth: hovered ? 1.6 : 0.8)
    }

    private func strokeHighlight(_ ctx: inout GraphicsContext, _ shape: Path, rect: CGRect) {
        ctx.stroke(shape, with: .color(ColorScale.highlight.opacity(0.35)), lineWidth: 7)
        ctx.stroke(shape, with: .color(ColorScale.highlight), lineWidth: 2.5)
        if rect.width < 24 && rect.height < 24 {
            let ring = Path(ellipseIn: CGRect(x: rect.midX - 13, y: rect.midY - 13, width: 26, height: 26))
            ctx.stroke(ring, with: .color(ColorScale.highlight), lineWidth: 2.5)
        }
    }

    /// Yeni tahminde kısa beyaz parlama; bulunan yerde birkaç kez yeşil nabız.
    private func strokePulse(_ ctx: inout GraphicsContext, _ shape: Path, _ pulse: Pulse, now: Date) {
        let t = min(1, max(0, now.timeIntervalSince(pulse.start) / pulse.duration))
        if pulse.win {
            let wave = pow(sin(t * .pi * 3), 2) * (1 - t)
            ctx.stroke(shape, with: .color(ColorScale.found.opacity(0.85 * wave)), lineWidth: 4 + 10 * wave)
        } else {
            let fade = (1 - t) * (1 - t)
            ctx.stroke(shape, with: .color(.white.opacity(0.9 * fade)), lineWidth: 2 + 9 * t)
        }
    }

    /// Tahmin edilen her yerin adı mutlaka yazılır. Önce gizli yer, sonra en yakın tahminler yerleşir.
    /// Ad kendi yerinin üstüne sığmıyorsa ya da başka bir adla çakışıyorsa yakındaki boş bir yere
    /// (gerekirse komşunun üstüne) kayar ve ince bir çizgiyle yerine bağlanır; ekran kenarında içeri itilir.
    private func drawLabels(_ ctx: inout GraphicsContext, _ items: [LabelItem], size: CGSize) {
        guard !items.isEmpty else { return }
        func rank(_ p: Place) -> Int { p == game.answer ? -1 : (game.guess(for: p)?.distance ?? .max) }
        let k = Platform.drawScale
        let font = Font.system(size: 11 * k, weight: .semibold)
        var placed: [CGRect] = []
        for item in items.sorted(by: { rank($0.place) < rank($1.place) }) {
            // Vurgulanan ya da üzerine gelinen yerin zaten kendi etiketi var.
            if item.place == hovered || item.place == game.highlighted { continue }
            let text = ctx.resolve(Text(item.place.name).font(font).foregroundStyle(palette.labelText))
            let halo = ctx.resolve(Text(item.place.name).font(font).foregroundStyle(palette.labelHalo))
            let m = text.measure(in: CGSize(width: 400 * k, height: 40 * k))
            let anchor = item.point
            guard anchor.x > -40, anchor.y > -40, anchor.x < size.width + 40, anchor.y < size.height + 40 else { continue }
            let box = LabelLayout.place(anchor: anchor, width: m.width + 6 * k, height: 16 * k, in: size, avoiding: placed)
            placed.append(box)
            let center = CGPoint(x: box.midX, y: box.midY)
            if hypot(center.x - anchor.x, center.y - anchor.y) > 10 * k {
                var line = Path()
                line.move(to: anchor)
                line.addLine(to: LabelLayout.edgePoint(of: box, toward: anchor))
                ctx.stroke(line, with: .color(palette.labelHalo), lineWidth: 3 * k)
                ctx.stroke(line, with: .color(palette.labelText.opacity(0.8)), lineWidth: 1 * k)
                ctx.fill(Path(ellipseIn: CGRect(x: anchor.x - 2 * k, y: anchor.y - 2 * k, width: 4 * k, height: 4 * k)),
                         with: .color(palette.labelText))
            }
            for (dx, dy) in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1), (-0.8, -0.8), (0.8, 0.8), (-0.8, 0.8), (0.8, -0.8)] {
                ctx.draw(halo, at: CGPoint(x: center.x + dx * k, y: center.y + dy * k))
            }
            ctx.draw(text, at: center)
        }
    }

    // MARK: Renkler

    private struct Palette {
        let sea, backgroundLand, border, markerStroke, unguessed: Color
        let space, seaLight, atmosphere, globeShade, graticule, labelText, labelHalo: Color
    }

    private var palette: Palette {
        colorScheme == .dark
            ? Palette(sea: Color(red: 0.07, green: 0.09, blue: 0.13), backgroundLand: Color(white: 0.17),
                      border: Color.black.opacity(0.6), markerStroke: Color.white.opacity(0.5), unguessed: Color(white: 0.30),
                      space: Color(red: 0.03, green: 0.035, blue: 0.05), seaLight: Color(red: 0.11, green: 0.15, blue: 0.2),
                      atmosphere: Color(red: 0.35, green: 0.59, blue: 1).opacity(0.28), globeShade: Color.black.opacity(0.45),
                      graticule: Color(red: 0.55, green: 0.67, blue: 0.86).opacity(0.10),
                      labelText: Color(white: 0.96), labelHalo: Color.black.opacity(0.75))
            : Palette(sea: Color(red: 0.89, green: 0.93, blue: 0.97), backgroundLand: Color(white: 0.95),
                      border: Color.white, markerStroke: Color.black.opacity(0.35), unguessed: Color(white: 0.82),
                      space: Color(red: 0.96, green: 0.965, blue: 0.98), seaLight: Color(red: 0.95, green: 0.97, blue: 0.99),
                      atmosphere: Color(red: 0.47, green: 0.67, blue: 0.9).opacity(0.35), globeShade: Color(red: 0.16, green: 0.24, blue: 0.4).opacity(0.18),
                      graticule: Color(red: 0.24, green: 0.4, blue: 0.63).opacity(0.12),
                      labelText: Color(white: 0.11), labelHalo: Color.white.opacity(0.85))
    }

    private func fill(for place: Place) -> Color {
        if place == game.answer {
            if game.status == .won { return ColorScale.found }
            if game.status == .lost { return ColorScale.answerReveal }
        }
        guard let g = game.guess(for: place) else { return palette.unguessed }
        return ColorScale.color(forDistance: g.distance, max: places.maxDistance)
    }

    /// Haritada adı yazılacak yerler: tahmin edilenler ve oyun bitince gizli yer.
    private func showsLabel(_ place: Place) -> Bool {
        game.guess(for: place) != nil || (game.isOver && place == game.answer)
    }

    private func hoverLabel(for place: Place) -> String? {
        if let g = game.guess(for: place) {
            if place == game.answer { return "\(place.name) ✓" }
            if g.distance == 0 { return "\(place.name) · \(L("neighbor"))" }
            return showDistance ? "\(place.name) · \(TurkishText.formatKm(g.distance))" : place.name
        }
        return game.isOver ? place.name : nil
    }

    // MARK: Geometri sorguları

    private var highlightIndex: Int? {
        game.highlighted.flatMap { places.places.firstIndex(of: $0) }
    }

    /// Vurgulanan yerin ekrandaki konumu (etiket için).
    private func highlightAnchor(size: CGSize) -> (point: CGPoint, small: Bool)? {
        guard let i = highlightIndex else { return nil }
        if places.usesGlobe {
            let shape = places.globeGeometry.places[i]
            let proj = GlobeProjection(size: size, zoom: zoom, lon: a, lat: b)
            let p = proj.project(lon: shape.label.lon, lat: shape.label.lat)
            guard p.cosc > 0 else { return nil }
            let half = max(8, shape.angular * proj.radius * .pi / 180 / 2)
            return (CGPoint(x: p.point.x, y: p.point.y - min(half, 60)), half < 12)
        }
        let geometry = places.geometry
        let r = geometry.paths[i].boundingRect.applying(MapCamera.transform(size: size, bounds: geometry.bounds, cam: cam))
        return (CGPoint(x: r.midX, y: r.minY), r.width < 24 && r.height < 24)
    }

    private func place(at point: CGPoint, size: CGSize) -> Place? {
        places.usesGlobe ? globePlace(at: point, size: size) : flatPlace(at: point, size: size)
    }

    private func flatPlace(at point: CGPoint, size: CGSize) -> Place? {
        let geometry = places.geometry
        let transform = MapCamera.transform(size: size, bounds: geometry.bounds, cam: cam)
        let local = point.applying(transform.inverted())
        for (i, path) in geometry.paths.enumerated() where path.boundingRect.contains(local) && path.contains(local) {
            return places.places[i]
        }
        // Küçük yerlerin işaret noktalarına da isabet edilebilsin.
        for (i, path) in geometry.paths.enumerated() {
            let r = path.boundingRect.applying(transform)
            if r.width < markerThreshold && r.height < markerThreshold,
               hypot(point.x - r.midX, point.y - r.midY) <= markerRadius + 3 {
                return places.places[i]
            }
        }
        return nil
    }

    private func globePlace(at point: CGPoint, size: CGSize) -> Place? {
        let globe = places.globeGeometry
        let proj = GlobeProjection(size: size, zoom: zoom, lon: a, lat: b)
        guard let ll = proj.unproject(point) else { return nil }
        for (i, shape) in globe.places.enumerated() where GlobeGeometry.contains(shape.rings, lon: ll.lon, lat: ll.lat) {
            return places.places[i]
        }
        let pxPerDeg = proj.radius * .pi / 180
        for (i, shape) in globe.places.enumerated() where shape.angular * pxPerDeg < markerThreshold {
            let p = proj.project(lon: shape.label.lon, lat: shape.label.lat)
            if p.cosc > 0, hypot(point.x - p.point.x, point.y - p.point.y) <= markerRadius + 3 { return places.places[i] }
        }
        return nil
    }
}

// MARK: - Renk skalası

/// Harita köşesindeki lejant: kategorinin mesafelerine göre km işaretleri.
struct LegendView: View {
    let places: PlaceSet
    @AppStorage(AppSettings.showDistanceKey) private var showDistance = true

    private var max: Int { places.maxDistance }

    private func nice(_ v: Double) -> Int {
        let p = pow(10, floor(log10(v)))
        return Int(Swift.max(p, (v / p).rounded() * p))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(stops: (0...10).map { i in
                    let t = Double(i) / 10
                    return .init(color: ColorScale.color(forDistance: Int(t * t * Double(max)), max: max), location: t)
                }, startPoint: .leading, endPoint: .trailing))
                .frame(height: 8 * Platform.drawScale)
            ZStack {
                Text(L(showDistance ? "neighbor" : "near")).frame(maxWidth: .infinity, alignment: .leading)
                if showDistance { Text(TurkishText.formatKm(nice(Double(max) * 0.25))) }
                Text(showDistance ? TurkishText.formatKm(nice(Double(max))) : L("far"))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10 * Platform.drawScale))
            .foregroundStyle(.secondary)
        }
        .frame(width: 180 * Platform.drawScale)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .allowsHitTesting(false)
    }
}

/// Harita adlarının yerleşimi (web'de `placeLabel`, aynı aday sırası).
enum LabelLayout {
    /// Ad kutusunu yerin çevresinde çakışmayan ilk adaya koyar; hiçbiri boş değilse en az çakışanı seçer.
    static func place(anchor: CGPoint, width w: CGFloat, height h: CGFloat, in size: CGSize, avoiding placed: [CGRect]) -> CGRect {
        let side = w / 2 + 8
        let offsets: [(CGFloat, CGFloat)] = [
            (0, 0), (0, -h * 1.1), (0, h * 1.1), (side, 0), (-side, 0),
            (side, -h * 1.1), (-side, -h * 1.1), (side, h * 1.1), (-side, h * 1.1),
            (0, -h * 2.2), (0, h * 2.2), (0, -h * 3.3), (0, h * 3.3),
            (side * 1.6, 0), (-side * 1.6, 0), (side, -h * 2.2), (-side, h * 2.2),
        ]
        var best: CGRect?
        var bestOverlap = CGFloat.infinity
        for (dx, dy) in offsets {
            let x = min(max(anchor.x + dx - w / 2, 2), max(size.width - 2 - w, 2))
            let y = min(max(anchor.y + dy - h / 2, 2), max(size.height - 2 - h, 2))
            let box = CGRect(x: x, y: y, width: w, height: h)
            let overlap = placed.reduce(CGFloat(0)) { sum, r in
                let i = r.intersection(box)
                return i.isNull ? sum : sum + i.width * i.height
            }
            if overlap == 0 { return box }
            if overlap < bestOverlap { bestOverlap = overlap; best = box }
        }
        return best!
    }

    /// Kutunun kenarında, verilen noktaya en yakın yer (bağlantı çizgisinin ucu).
    static func edgePoint(of box: CGRect, toward p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, box.minX), box.maxX), y: min(max(p.y, box.minY), box.maxY))
    }
}
