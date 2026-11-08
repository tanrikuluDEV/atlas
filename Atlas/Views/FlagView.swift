import SwiftUI

/// Ülkenin bayrağı: emoji, KKTC için (emojisi olmadığından) çizilmiş küçük bayrak. İllerde hiçbir şey çizmez.
/// Web karşılığı `flagHTML` (app.js).
struct FlagView: View {
    let place: Place
    /// Yazı boyutuna göre ölçeklensin diye çizilen bayrağın yüksekliği.
    var height: CGFloat = 13

    var body: some View {
        if let flag = place.flag {
            Text(flag).accessibilityHidden(true)
        } else if place.iso2 == "CY-N" {
            NorthCyprusFlag()
                .frame(width: height * 1.5, height: height)
                .accessibilityHidden(true)
        }
    }
}

/// KKTC bayrağı: beyaz zemin, üstte ve altta kırmızı şerit, ortada kırmızı ay yıldız.
struct NorthCyprusFlag: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let red = Color(red: 0.89, green: 0.04, blue: 0.09)
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: h * 0.08), with: .color(.white))
            ctx.fill(Path(CGRect(x: 0, y: h * 0.1, width: w, height: h * 0.11)), with: .color(red))
            ctx.fill(Path(CGRect(x: 0, y: h * 0.79, width: w, height: h * 0.11)), with: .color(red))
            // Ay: iki dairenin farkı.
            let c = CGPoint(x: w * 0.44, y: h * 0.5), r = h * 0.2
            var moon = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let ri = r * 0.8
            moon = moon.subtracting(Path(ellipseIn: CGRect(x: c.x - ri + r * 0.32, y: c.y - ri, width: ri * 2, height: ri * 2)))
            ctx.fill(moon, with: .color(red))
            ctx.fill(star(center: CGPoint(x: w * 0.6, y: h * 0.5), radius: h * 0.1), with: .color(red))
            ctx.stroke(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: h * 0.08),
                       with: .color(.black.opacity(0.15)), lineWidth: 0.5)
        }
    }

    private func star(center: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? radius : radius * 0.4
            // Bir köşesi sola (aya) baksın.
            let a = Double(i) * .pi / 5 + .pi
            let pt = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
