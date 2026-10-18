// Uygulama ikonlarını Claude Design'daki "Atlas 1a · Küre-pin" tasarımından çizer:
// iOS (açık + koyu), macOS (tüm boyutlar; 64 px ve altı sadeleştirilmiş), Apple TV (katmanlı ikon +
// üst raf görselleri) ve web (PWA ikonları, apple-touch-icon, favicon, paylaşım görseli).
// Kullanım: swift tools/make_icons.swift
import AppKit
import CoreText

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Atlas/Assets.xcassets")
let webIcons = root.appendingPathComponent("web/icons")

CTFontManagerRegisterFontsForURL(root.appendingPathComponent("Atlas/Resources/BricolageGrotesque-ExtraBold.ttf") as CFURL, .process, nil)

let orange = CGColor(srgbRed: 0.949, green: 0.400, blue: 0.265, alpha: 1)
let navy = CGColor(srgbRed: 0.077, green: 0.125, blue: 0.187, alpha: 1)
let cream = CGColor(srgbRed: 0.977, green: 0.966, blue: 0.944, alpha: 1)

/// İşaretin ayrıntı düzeyi: tam (küre çizgileriyle), 64 px (çember + ekvator), 32 px (dolu daire), 16 px (yalnız pin).
enum Detail { case full, small64, small32, small16 }

func pinPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 50, y: 94))
    p.addCurve(to: CGPoint(x: 16, y: 38), control1: CGPoint(x: 50, y: 94), control2: CGPoint(x: 16, y: 60))
    p.addArc(center: CGPoint(x: 50, y: 38), radius: 34, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
    p.addCurve(to: CGPoint(x: 50, y: 94), control1: CGPoint(x: 84, y: 60), control2: CGPoint(x: 50, y: 94))
    p.closeSubpath()
    return p
}

/// İşareti `box` karesine çizer (bağlam y-aşağı çevrilmiş olmalı; SVG koordinatları 100×100).
func drawMark(_ ctx: CGContext, box: CGRect, detail: Detail, pin: CGColor, lines: CGColor, equator: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: box.minX, y: box.minY)
    ctx.scaleBy(x: box.width / 100, y: box.height / 100)
    ctx.addPath(pinPath()); ctx.setFillColor(pin); ctx.fillPath()
    ctx.setStrokeColor(lines)
    switch detail {
    case .full:
        ctx.setLineWidth(4)
        ctx.strokeEllipse(in: CGRect(x: 30, y: 18, width: 40, height: 40))
        ctx.strokeEllipse(in: CGRect(x: 42, y: 18, width: 16, height: 40))
        ctx.setStrokeColor(equator)
        ctx.move(to: CGPoint(x: 30, y: 38)); ctx.addLine(to: CGPoint(x: 70, y: 38)); ctx.strokePath()
    case .small64:
        ctx.setLineWidth(6)
        ctx.strokeEllipse(in: CGRect(x: 31, y: 19, width: 38, height: 38))
        ctx.move(to: CGPoint(x: 31, y: 38)); ctx.addLine(to: CGPoint(x: 69, y: 38)); ctx.strokePath()
    case .small32:
        ctx.setFillColor(lines)
        ctx.fillEllipse(in: CGRect(x: 36, y: 24, width: 28, height: 28))
    case .small16:
        break
    }
    ctx.restoreGState()
}

func drawText(_ ctx: CGContext, _ text: String, size: CGFloat, color: CGColor, at origin: CGPoint) -> CGFloat {
    let font = CTFontCreateWithName("BricolageGrotesque96pt-ExtraBold" as CFString, size, nil)
    let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: -0.02 * size])
    let line = CTLineCreateWithAttributedString(attr)
    // Bağlam y-aşağı; metin için yerel olarak düzelt. `origin.y` taban çizgisi.
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
    return CTLineGetTypographicBounds(line, nil, nil, nil)
}

func textWidth(_ text: String, size: CGFloat) -> CGFloat {
    let font = CTFontCreateWithName("BricolageGrotesque96pt-ExtraBold" as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: -0.02 * size]))
    return CTLineGetTypographicBounds(line, nil, nil, nil)
}

/// y-aşağı koordinatlı bir bitmap üzerinde çizer ve PNG olarak yazar.
func png(_ url: URL, _ w: Int, _ h: Int, opaque: Bool = true, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func centered(_ size: CGFloat, in w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: (w - size) / 2, y: (h - size) / 2, width: size, height: size)
}

let info: [String: Any] = ["author": "xcode", "version": 1]
func writeContents(_ object: [String: Any], to dir: URL) {
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        .write(to: dir.appendingPathComponent("Contents.json"))
}

// MARK: - iOS ve macOS

let appIcon = assets.appendingPathComponent("AppIcon.appiconset")
try? FileManager.default.removeItem(at: appIcon)

// iOS: tam kare (sistem köşeleri yuvarlar). İşaret, ikonun %62'si.
png(appIcon.appendingPathComponent("icon-ios.png"), 1024, 1024) { ctx in
    ctx.setFillColor(orange); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    drawMark(ctx, box: centered(1024 * 0.622, in: 1024, 1024), detail: .full, pin: navy, lines: cream, equator: cream)
}
png(appIcon.appendingPathComponent("icon-ios-dark.png"), 1024, 1024) { ctx in
    ctx.setFillColor(navy); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    drawMark(ctx, box: centered(1024 * 0.622, in: 1024, 1024), detail: .full, pin: orange, lines: navy, equator: navy)
}

/// macOS: 128 px ve üstü Apple ızgarasındaki yuvarlatılmış kare (gölgeli); küçük boyutlarda kare
/// tüm alanı kaplar ve işaret sadeleşir (tasarımdaki 64 / 32 / 16 sürümleri).
func macIcon(_ px: Int) -> (CGContext) -> Void {
    { ctx in
        let s = CGFloat(px)
        if px >= 128 {
            let tile = centered(s * 824 / 1024, in: s, s)
            let path = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: s * 0.012), blur: s * 0.03,
                          color: CGColor(srgbRed: 0.077, green: 0.125, blue: 0.187, alpha: 0.3))
            ctx.addPath(path); ctx.setFillColor(orange); ctx.fillPath()
            ctx.restoreGState()
            drawMark(ctx, box: centered(tile.width * 90 / 146, in: s, s), detail: .full, pin: navy, lines: cream, equator: cream)
        } else {
            let detail: Detail = px <= 16 ? .small16 : px <= 32 ? .small32 : .small64
            let ratio: CGFloat = px <= 16 ? 13 / 16 : px <= 32 ? 24 / 32 : 44 / 64
            let tile = CGRect(x: 0, y: 0, width: s, height: s)
            ctx.addPath(CGPath(roundedRect: tile, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil))
            ctx.setFillColor(orange); ctx.fillPath()
            drawMark(ctx, box: centered(s * ratio, in: s, s), detail: detail, pin: navy, lines: cream, equator: cream)
        }
    }
}

var images: [[String: Any]] = [
    ["filename": "icon-ios.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
    ["appearances": [["appearance": "luminosity", "value": "dark"]],
     "filename": "icon-ios-dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
]
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon-mac-\(pt)@\(scale)x.png"
        png(appIcon.appendingPathComponent(name), pt * scale, pt * scale, opaque: false, macIcon(pt * scale))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)"])
    }
}
writeContents(["images": images, "info": info], to: appIcon)

// MARK: - Apple TV

let brand = assets.appendingPathComponent("TVAppIcon.brandassets")
try? FileManager.default.removeItem(at: brand)

func imageset(_ dir: URL, scales: [Int], _ w: Int, _ h: Int, opaque: Bool, _ draw: @escaping (CGContext, CGFloat) -> Void) {
    var list: [[String: String]] = []
    for s in scales {
        let name = "image@\(s)x.png"
        png(dir.appendingPathComponent(name), w * s, h * s, opaque: opaque) { draw($0, CGFloat(s)) }
        list.append(["filename": name, "idiom": "tv", "scale": "\(s)x"])
    }
    writeContents(["images": list, "info": info], to: dir)
}

/// Katmanlı ikon: arkada turuncu zemin, önde pin (odakta paralaks).
func imagestack(_ dir: URL, _ w: Int, _ h: Int, scales: [Int]) {
    let back = dir.appendingPathComponent("Back.imagestacklayer")
    imageset(back.appendingPathComponent("Content.imageset"), scales: scales, w, h, opaque: true) { ctx, s in
        ctx.setFillColor(orange); ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w) * s, height: CGFloat(h) * s))
    }
    writeContents(["info": info], to: back)
    let front = dir.appendingPathComponent("Front.imagestacklayer")
    imageset(front.appendingPathComponent("Content.imageset"), scales: scales, w, h, opaque: false) { ctx, s in
        let W = CGFloat(w) * s, H = CGFloat(h) * s
        drawMark(ctx, box: centered(H * 0.66, in: W, H), detail: .full, pin: navy, lines: cream, equator: cream)
    }
    writeContents(["info": info], to: front)
    writeContents(["layers": [["filename": "Front.imagestacklayer"], ["filename": "Back.imagestacklayer"]], "info": info], to: dir)
}

/// Üst raf: koyu zeminde açık renk logo ve "Atlas" yazısı.
func topShelf(_ ctx: CGContext, _ W: CGFloat, _ H: CGFloat) {
    ctx.setFillColor(navy); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let mark = H * 0.36, size = H * 0.3, gap = H * 0.06
    let total = mark + gap + textWidth("Atlas", size: size)
    let x = (W - total) / 2
    drawMark(ctx, box: CGRect(x: x, y: (H - mark) / 2, width: mark, height: mark), detail: .full, pin: cream, lines: navy, equator: orange)
    _ = drawText(ctx, "Atlas", size: size, color: cream, at: CGPoint(x: x + mark + gap, y: H / 2 + size * 0.35))
}

imagestack(brand.appendingPathComponent("App Icon.imagestack"), 400, 240, scales: [1, 2])
imagestack(brand.appendingPathComponent("App Icon - App Store.imagestack"), 1280, 768, scales: [1])
imageset(brand.appendingPathComponent("Top Shelf Image.imageset"), scales: [1, 2], 1920, 720, opaque: true) { ctx, s in topShelf(ctx, 1920 * s, 720 * s) }
imageset(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), scales: [1, 2], 2320, 720, opaque: true) { ctx, s in topShelf(ctx, 2320 * s, 720 * s) }
writeContents(["assets": [
    ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
    ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
    ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
], "info": info], to: brand)

// MARK: - Web

/// PWA ikonları "maskable" da kullanıldığı için işaret güvenli alanda kalır (%56).
for (name, px) in [("icon-192.png", 192), ("icon-512.png", 512), ("apple-touch-icon.png", 180)] {
    png(webIcons.appendingPathComponent(name), px, px) { ctx in
        let s = CGFloat(px)
        ctx.setFillColor(orange); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        drawMark(ctx, box: centered(s * 0.58, in: s, s), detail: .full, pin: navy, lines: cream, equator: cream)
    }
}
png(webIcons.appendingPathComponent("favicon-32.png"), 32, 32, opaque: false, macIcon(32))

// Paylaşım görseli (Open Graph, 1200×630): açık zeminde yatay logo.
png(webIcons.appendingPathComponent("og.png"), 1200, 630) { ctx in
    ctx.setFillColor(cream); ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 630))
    let mark: CGFloat = 220, size: CGFloat = 190, gap: CGFloat = 40
    let x = (1200 - (mark + gap + textWidth("Atlas", size: size))) / 2
    drawMark(ctx, box: CGRect(x: x, y: (630 - mark) / 2, width: mark, height: mark), detail: .full, pin: navy, lines: cream, equator: orange)
    _ = drawText(ctx, "Atlas", size: size, color: navy, at: CGPoint(x: x + mark + gap, y: 315 + size * 0.35))
}
print("ikonlar yazıldı")
