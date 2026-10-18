import SwiftUI

// MARK: - Düz harita

/// Bir kategorinin sınırlarının düzlem projeksiyonu; kategori başına bir kez hesaplanır.
final class MapGeometry {
    /// `set.places` ile aynı sırada.
    let paths: [Path]
    let backgroundPaths: [Path]
    /// Kameranın odaklanacağı alan: yerin ana toprağı (uzak adalar ve deniz aşırı topraklar hariç).
    let focusRects: [CGRect]
    /// Adın yazılacağı nokta: en büyük parçanın merkezi.
    let labelPoints: [CGPoint]
    /// Haritada gösterilecek alan (projeksiyon koordinatlarında).
    let bounds: CGRect

    init(set: PlaceSet) {
        // Görünüm alanının orta enlemine göre eşdikdörtgen projeksiyon: x = boylam·cos(φ₀), y = -enlem
        let midLat = set.viewBounds.map { $0.midY } ?? 39
        let k = cos(min(abs(midLat), 60) * .pi / 180)
        let shift = set.shiftLongitude

        func project(_ ring: [[Double]]) -> [CGPoint] {
            // Kaydırma halkanın tamamına uygulanır; noktaları tek tek kaydırmak 0° boylamını
            // kesen şekilleri yırtar. (Natural Earth halkaları 180°'de zaten bölünmüştür.)
            let meanLon = ring.reduce(0) { $0 + $1[0] } / Double(ring.count)
            let dx = shift(meanLon) - meanLon
            return ring.map { CGPoint(x: ($0[0] + dx) * k, y: -$0[1]) }
        }

        func path(_ rings: [[CGPoint]]) -> Path {
            var path = Path()
            for ring in rings where ring.count > 2 {
                path.addLines(ring)
                path.closeSubpath()
            }
            return path
        }

        var paths: [Path] = [], focus: [CGRect] = [], labels: [CGPoint] = []
        for place in set.places {
            let rings = place.rings.filter { !$0.isEmpty }.map(project)
            paths.append(path(rings))
            let rects = rings.map(Self.boundingRect)
            focus.append(Self.mainlandRect(rects))
            var mainIndex = 0
            for (i, r) in rects.enumerated() where r.width * r.height > rects[mainIndex].width * rects[mainIndex].height {
                mainIndex = i
            }
            labels.append(rings.isEmpty ? .zero : Self.centroid(rings[mainIndex]))
        }
        self.paths = paths
        focusRects = focus
        labelPoints = labels
        backgroundPaths = set.background.map { path($0.filter { !$0.isEmpty }.map(project)) }
        if let v = set.viewBounds {
            bounds = CGRect(x: v.minX * k, y: -v.maxY, width: v.width * k, height: v.height)
        } else {
            bounds = paths.reduce(CGRect.null) { $0.union($1.boundingRect) }
        }
    }

    static func boundingRect(_ pts: [CGPoint]) -> CGRect {
        guard let f = pts.first else { return .null }
        var r = CGRect(origin: f, size: .zero)
        for p in pts { r = r.union(CGRect(origin: p, size: .zero)) }
        return r
    }

    /// En büyük parça ile ona yakın parçaların (ör. Korsika, Sicilya) kutusu. Norveç'te Svalbard,
    /// Fransa'da Fransız Guyanası, ABD'de Alaska ve Hawaii böylece kadraja girmez.
    static func mainlandRect(_ rects: [CGRect]) -> CGRect {
        guard let main = rects.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return .null }
        let reach = max(main.width, main.height) * 0.5
        let near = main.insetBy(dx: -reach, dy: -reach)
        return rects.filter { near.intersects($0) }.reduce(main) { $0.union($1) }
    }

    /// Halkanın alan ağırlıklı merkezi.
    static func centroid(_ pts: [CGPoint]) -> CGPoint {
        var a = 0.0, cx = 0.0, cy = 0.0
        for i in pts.indices {
            let p = pts[i], q = pts[(i + pts.count - 1) % pts.count]
            let f = q.x * p.y - p.x * q.y
            a += f; cx += (q.x + p.x) * f; cy += (q.y + p.y) * f
        }
        guard abs(a) > 1e-9 else {
            let n = CGFloat(pts.count)
            return CGPoint(x: pts.reduce(0) { $0 + $1.x } / n, y: pts.reduce(0) { $0 + $1.y } / n)
        }
        return CGPoint(x: cx / (3 * a), y: cy / (3 * a))
    }
}

// MARK: - Küre

/// Dünya kategorisinin küre geometrisi. Noktalar birim küre üzerinde saklanır; döndürme ve
/// izdüşüm her karede hızlıca yapılır.
final class GlobeGeometry {
    struct Ring {
        /// x, y, z art arda (birim küre).
        let vec: [Float]
        /// [boylam, enlem]; isabet testi için.
        let lonLat: [[Double]]
        /// Boylam/enlem kutusu (x = boylam, y = enlem).
        let rect: CGRect
    }

    struct Shape {
        let rings: [Ring]
        /// Ad noktası (boylam, enlem).
        let label: (lon: Double, lat: Double)
        /// Odak: ana toprağın merkezi ve açısal boyutu (derece).
        let focus: (lon: Double, lat: Double, size: Double)
        /// Tüm toprakların açısal boyutu (derece); küçük yer işaretleri için.
        let angular: Double
    }

    let places: [Shape]
    let background: [[Ring]]

    init(set: PlaceSet) {
        func rings(_ raw: [[[Double]]]) -> [Ring] {
            raw.filter { $0.count > 2 }.map { ring in
                var vec = [Float]()
                vec.reserveCapacity(ring.count * 3)
                for p in ring {
                    let l = p[0] * .pi / 180, f = p[1] * .pi / 180
                    vec += [Float(cos(f) * cos(l)), Float(cos(f) * sin(l)), Float(sin(f))]
                }
                let pts = ring.map { CGPoint(x: $0[0], y: $0[1]) }
                return Ring(vec: vec, lonLat: ring, rect: MapGeometry.boundingRect(pts))
            }
        }

        places = set.places.map { place in
            let rs = rings(place.rings)
            let rect = rs.reduce(CGRect.null) { $0.union($1.rect) }
            let focus = MapGeometry.mainlandRect(rs.map(\.rect))
            let main = rs.max { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
            let c = main.map { MapGeometry.centroid($0.lonLat.map { CGPoint(x: $0[0], y: $0[1]) }) } ?? .zero
            let mid = focus.midY
            let size = max(focus.width * cos(mid * .pi / 180), focus.height)
            let angular = max(rect.width * cos(rect.midY * .pi / 180), rect.height)
            return Shape(rings: rs, label: (c.x, c.y), focus: (focus.midX, mid, size), angular: angular)
        }
        background = set.background.map(rings)
    }

    /// Noktanın halkaların içinde olup olmadığı (boylam/enlem düzleminde, çift-tek kuralı).
    static func contains(_ rings: [Ring], lon: Double, lat: Double) -> Bool {
        var inside = false
        for r in rings where r.rect.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: lon, y: lat)) {
            let pts = r.lonLat
            var j = pts.count - 1
            for i in pts.indices {
                let (xi, yi, xj, yj) = (pts[i][0], pts[i][1], pts[j][0], pts[j][1])
                if (yi > lat) != (yj > lat), lon < (xj - xi) * (lat - yi) / (yj - yi) + xi { inside.toggle() }
                j = i
            }
        }
        return inside
    }
}

/// Küre izdüşümü: merkezdeki boylam/enlem ve ekrandaki yarıçap.
struct GlobeProjection {
    let center: CGPoint
    let radius: CGFloat
    private let cl: Float, sl: Float, cp: Float, sp: Float

    init(size: CGSize, zoom: CGFloat, lon: Double, lat: Double) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        radius = (min(size.width, size.height) / 2 - MapCamera.padding) * zoom
        let l = lon * .pi / 180, p = lat * .pi / 180
        cl = Float(cos(l)); sl = Float(sin(l)); cp = Float(cos(p)); sp = Float(sin(p))
    }

    /// Boylam/enlemden ekrana; `cosc > 0` ise görünür (ön yüz).
    func project(lon: Double, lat: Double) -> (point: CGPoint, cosc: Float) {
        let l = lon * .pi / 180, f = lat * .pi / 180
        return project(x: Float(cos(f) * cos(l)), y: Float(cos(f) * sin(l)), z: Float(sin(f)))
    }

    @inline(__always)
    func project(x: Float, y: Float, z: Float) -> (point: CGPoint, cosc: Float) {
        let a = x * cl + y * sl, b = y * cl - x * sl
        let cosc = sp * z + cp * a
        let py = cp * z - sp * a
        return (CGPoint(x: center.x + radius * CGFloat(b), y: center.y - radius * CGFloat(py)), cosc)
    }

    /// Ekrandan boylam/enleme; küre dışındaysa nil.
    func unproject(_ p: CGPoint) -> (lon: Double, lat: Double)? {
        let xp = Double((p.x - center.x) / radius), yp = Double(-(p.y - center.y) / radius)
        let d2 = xp * xp + yp * yp
        guard d2 <= 1 else { return nil }
        let cosc = sqrt(1 - d2)
        let (cl, sl, cp, sp) = (Double(self.cl), Double(self.sl), Double(self.cp), Double(self.sp))
        let a = cp * cosc - sp * yp, z = sp * cosc + cp * yp, b = xp
        let x = a * cl - b * sl, y = a * sl + b * cl
        return (atan2(y, x) * 180 / .pi, asin(max(-1, min(1, z))) * 180 / .pi)
    }

    /// Halkaları yola ekler; arka yüzdeki noktalar ufuk çemberine yaslanır. Görünür halka yoksa false.
    func trace(_ rings: [GlobeGeometry.Ring], into path: inout Path) -> Bool {
        var any = false
        for ring in rings {
            let v = ring.vec
            let n = v.count / 3
            var visible = false
            for i in 0..<n where sp * v[i * 3 + 2] + cp * (v[i * 3] * cl + v[i * 3 + 1] * sl) > 0 {
                visible = true
                break
            }
            guard visible else { continue }
            any = true
            for i in 0..<n {
                let x = v[i * 3], y = v[i * 3 + 1], z = v[i * 3 + 2]
                let a = x * cl + y * sl
                var px = y * cl - x * sl, py = cp * z - sp * a
                if sp * z + cp * a < 0 {
                    let d = max(sqrt(px * px + py * py), 1e-6)
                    px /= d; py /= d
                }
                let pt = CGPoint(x: center.x + radius * CGFloat(px), y: center.y - radius * CGFloat(py))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
        }
        return any
    }
}
