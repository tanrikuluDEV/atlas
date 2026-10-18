// world.json'daki her ülke çifti için en yakın sınırlar arası mesafeyi (km) hesaplayıp dosyaya yazar.
// Mesafe, bir ülkenin köşe noktalarından diğerinin sınır doğru parçalarına olan en kısa uzaklıktır;
// böylece uzun, düz ortak sınırlar sadeleştirmeden sonra da komşu (0 km) sayılır.
// Kullanım: swiftc -O tools/compute_distances.swift -o /tmp/compute_distances && /tmp/compute_distances
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let file = root.appendingPathComponent("Atlas/Resources/world.json")
var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
let countries = json["countries"] as! [[String: Any]]

let earthKm = 6371.0
let neighborKm = 5.0 // bu mesafenin altı komşu sayılır (sadeleştirme kaymalarını tolere eder)

struct V { var x, y, z: Double }
func unit(_ lon: Double, _ lat: Double) -> V {
    let l = lon * .pi / 180, p = lat * .pi / 180
    return V(x: cos(p) * cos(l), y: cos(p) * sin(l), z: sin(p))
}

struct Shape {
    var points: [V] = []
    var segments: [(V, V)] = []
    var minLat = 90.0, maxLat = -90.0
}

let shapes: [Shape] = countries.map { c in
    var s = Shape()
    for ring in c["rings"] as! [[[Double]]] {
        let vs = ring.map { unit($0[0], $0[1]) }
        s.points += vs
        for i in 0..<(vs.count - 1) { s.segments.append((vs[i], vs[i + 1])) }
        for p in ring { s.minLat = min(s.minLat, p[1]); s.maxLat = max(s.maxLat, p[1]) }
    }
    return s
}

@inline(__always) func sub(_ a: V, _ b: V) -> V { V(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
@inline(__always) func dot(_ a: V, _ b: V) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }

/// Birim küredeki noktanın doğru parçasına kiriş uzaklığının karesi (kısa mesafelerde yay uzunluğuna çok yakın).
@inline(__always) func segDist2(_ p: V, _ a: V, _ b: V) -> Double {
    let ab = sub(b, a), ap = sub(p, a)
    let len2 = dot(ab, ab)
    let t = len2 > 0 ? max(0, min(1, dot(ap, ab) / len2)) : 0
    let d = V(x: ap.x - ab.x * t, y: ap.y - ab.y * t, z: ap.z - ab.z * t)
    return dot(d, d)
}

func pointsToSegments(_ a: Shape, _ b: Shape, _ bound: Double) -> Double {
    var best = bound
    for p in a.points {
        for (s, e) in b.segments {
            let d = segDist2(p, s, e)
            if d < best { best = d }
        }
    }
    return best
}

func distanceKm(_ i: Int, _ j: Int) -> Int {
    let a = shapes[i], b = shapes[j]
    // Önce köşe–köşe en yakın çift (hızlı üst sınır), ardından köşe–kenar ile iyileştirme.
    var best = Double.infinity
    for p in a.points { for q in b.points { let d = dot(sub(p, q), sub(p, q)); if d < best { best = d } } }
    best = pointsToSegments(a, b, best)
    best = pointsToSegments(b, a, best)
    let chord = sqrt(best)
    let km = 2 * asin(min(1, chord / 2)) * earthKm
    return km < neighborKm ? 0 : Int(km.rounded())
}

let n = shapes.count
var matrix = [[Int]](repeating: [Int](repeating: 0, count: n), count: n)
let lock = NSLock()
let start = Date()
DispatchQueue.concurrentPerform(iterations: n) { i in
    var row = [Int](repeating: 0, count: n)
    for j in (i + 1)..<n { row[j] = distanceKm(i, j) }
    lock.lock()
    for j in (i + 1)..<n { matrix[i][j] = row[j]; matrix[j][i] = row[j] }
    lock.unlock()
}
print("\(n) ülke, \(String(format: "%.1f", Date().timeIntervalSince(start))) sn")

json["distances"] = matrix
let out = try! JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes])
try! out.write(to: file)

// Kontrol çıktısı
let names = countries.map { $0["name"] as! String }
func idx(_ name: String) -> Int { names.firstIndex(of: name)! }
for name in ["Türkiye", "Almanya", "Fransa", "Brezilya"] {
    let i = idx(name)
    let neighbors = (0..<n).filter { $0 != i && matrix[i][$0] == 0 }.map { names[$0] }
    print(name, "komşular:", neighbors.joined(separator: ", "))
}
print("Türkiye–Japonya:", matrix[idx("Türkiye")][idx("Japonya")], "km; İspanya–Fas:", matrix[idx("İspanya")][idx("Fas")], "km")
