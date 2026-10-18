import CoreText
import SwiftUI

/// Claude Design'daki "Atlas 1a · Küre-pin" kimliği: renkler, logo işareti, yazı tipi,
/// açılış animasyonu ve seviye kartı. Web karşılığı `web/js/brand.js`.
enum Brand {
    // oklch(0.68 0.18 35), oklch(0.24 0.035 255), oklch(0.975 0.008 85)
    static let orange = Color(red: 0.949, green: 0.400, blue: 0.265)
    static let navy = Color(red: 0.077, green: 0.125, blue: 0.187)
    static let cream = Color(red: 0.977, green: 0.966, blue: 0.944)

    /// Logo yazı tipi (Bricolage Grotesque ExtraBold; yalnızca "Atlas" harfleri ve rakamlar gömülü).
    static func wordmark(_ size: CGFloat) -> Font { .custom("BricolageGrotesque96pt-ExtraBold", size: size) }

    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "BricolageGrotesque-ExtraBold", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// Damla biçimli harita pini (100×100 kutuda: uç (50, 94), baş merkezi (50, 38), yarıçap 34).
struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.midX + (x - 50) * s, y: rect.midY + (y - 50) * s) }
        var path = Path()
        path.move(to: p(50, 94))
        path.addCurve(to: p(16, 38), control1: p(50, 94), control2: p(16, 60))
        path.addArc(center: p(50, 38), radius: 34 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        path.addCurve(to: p(50, 94), control1: p(84, 60), control2: p(50, 94))
        path.closeSubpath()
        return path
    }
}

/// Logo işareti: pinin içinde küre (çember, meridyen, ekvator).
struct AtlasMark: View {
    var pin = Brand.navy
    var lines = Brand.cream
    var equator = Brand.orange

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            let o = CGPoint(x: (size.width - 100 * s) / 2, y: (size.height - 100 * s) / 2)
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: o.x + x * s, y: o.y + y * s, width: w * s, height: h * s)
            }
            ctx.fill(PinShape().path(in: r(0, 0, 100, 100)), with: .color(pin))
            let stroke = StrokeStyle(lineWidth: 4 * s)
            ctx.stroke(Path(ellipseIn: r(30, 18, 40, 40)), with: .color(lines), style: stroke)
            ctx.stroke(Path(ellipseIn: r(42, 18, 16, 40)), with: .color(lines), style: stroke)
            var line = Path()
            line.move(to: CGPoint(x: o.x + 30 * s, y: o.y + 38 * s))
            line.addLine(to: CGPoint(x: o.x + 70 * s, y: o.y + 38 * s))
            ctx.stroke(line, with: .color(equator), style: stroke)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// İçinde seviye numarası yazan turuncu pin.
struct LevelPin: View {
    let level: Int

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                PinShape().fill(Brand.orange)
                Text("\(level)")
                    .font(Brand.wordmark(size * 0.34))
                    .foregroundStyle(Brand.navy)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(width: size * 0.56)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2 - size * 0.12)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(L("level.n", ["n": level]))
    }
}

// MARK: - Açılış

/// Açılış animasyonu: pin yukarıdan düşüp seker, yere dalga yayılır, altında "Atlas" belirir.
struct SplashView: View {
    let onFinish: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropped = false
    @State private var ripple = 0 // 0 gizli, 1 küçük ve görünür, 2 büyüyüp kayboldu
    @State private var word = false

    private var k: CGFloat { Platform.isTV ? 2 : 1 }
    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            (dark ? Brand.navy : Brand.cream).ignoresSafeArea()
            VStack(spacing: 20 * k) {
                ZStack(alignment: .bottom) {
                    Ellipse()
                        .stroke(Brand.orange, lineWidth: 3 * k)
                        .frame(width: 40 * k, height: 12 * k)
                        .scaleEffect(ripple == 2 ? 2.6 : 0.2)
                        .opacity(ripple == 1 ? 0.9 : 0)
                        .offset(y: 4 * k)
                    AtlasMark(pin: dark ? Brand.cream : Brand.navy, lines: dark ? Brand.navy : Brand.cream)
                        .frame(width: 100 * k, height: 100 * k)
                        .offset(y: dropped ? 0 : -140 * k)
                        .opacity(dropped ? 1 : 0)
                }
                Text("Atlas")
                    .font(Brand.wordmark(48 * k))
                    .tracking(-1 * k)
                    .foregroundStyle(dark ? Brand.cream : Brand.navy)
                    .opacity(word ? 1 : 0)
                    .offset(y: word ? 0 : 12 * k)
            }
        }
        .task {
            guard !reduceMotion else { onFinish(); return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { dropped = true }
            try? await Task.sleep(for: .milliseconds(380))
            ripple = 1
            // Dalga önce küçük ve görünür çizilsin, sonra büyüyüp kaybolsun.
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(.easeOut(duration: 0.9)) { ripple = 2 }
            withAnimation(.easeOut(duration: 0.45).delay(0.1)) { word = true }
            try? await Task.sleep(for: .milliseconds(1100))
            onFinish()
        }
    }
}

// MARK: - Seviye kartı

/// Seviye, XP çubuğu ve bir sonraki seviyeye kalan puan. `reward` verilirse (sonuç penceresi)
/// kazanılan puan canlandırılır; seviye atlandıysa çubuk dolar, pin büyüyüp yeni numarayı gösterir.
struct LevelCard: View {
    let progress: LevelProgress
    var reward: Reward?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownLevel: Int
    @State private var bar: Double
    @State private var popped = false
    @State private var banner = false
    @State private var gain = false

    init(progress: LevelProgress, reward: Reward? = nil) {
        self.progress = progress
        self.reward = reward
        let animated = (reward?.gained ?? 0) > 0
        _shownLevel = State(initialValue: animated ? reward!.before.level : progress.level)
        _bar = State(initialValue: animated ? reward!.before.fraction : progress.fraction)
    }

    private var k: CGFloat { Platform.isTV ? 1.6 : 1 }
    private var mono: Font { .system(size: 12 * k, weight: .medium, design: .monospaced) }

    var body: some View {
        VStack(spacing: 12 * k) {
            if reward?.leveledUp == true {
                Text(L("level.up"))
                    .font(.system(size: 13 * k, weight: .medium, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(Brand.orange)
                    .opacity(banner ? 1 : 0)
                    .offset(y: banner ? 0 : 8)
            }
            HStack(spacing: 16 * k) {
                LevelPin(level: shownLevel)
                    .frame(width: 64 * k, height: 64 * k)
                    .scaleEffect(popped ? 1.25 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("level.n", ["n": shownLevel]))
                        .font(.system(size: 22 * k, weight: .heavy))
                    if let reward {
                        Text(reward.gained > 0 ? L("xp.gained", ["n": reward.gained]) : L("xp.none"))
                            .font(mono)
                            .foregroundStyle(reward.gained > 0 ? Brand.orange : Brand.cream.opacity(0.6))
                            .opacity(gain || reward.gained == 0 ? 1 : 0)
                            .offset(y: gain || reward.gained == 0 ? 0 : 10)
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Brand.cream.opacity(0.15))
                        Capsule().fill(Brand.orange).frame(width: max(10 * k, geo.size.width * bar))
                    }
                }
                .frame(height: 10 * k)
                HStack {
                    Text("\(format(progress.xp)) XP")
                    Spacer()
                    Text(format(progress.next))
                }
                .font(mono)
                .opacity(0.7)
            }
        }
        .padding(20 * k)
        .frame(maxWidth: .infinity)
        .foregroundStyle(Brand.cream)
        .background(Brand.navy, in: RoundedRectangle(cornerRadius: 20 * k))
        .task { await play() }
    }

    private func format(_ n: Int) -> String {
        n.formatted(.number.locale(L10n.shared.language.locale))
    }

    private func play() async {
        guard let reward, reward.gained > 0 else { return }
        if reduceMotion {
            shownLevel = reward.after.level; bar = reward.after.fraction; banner = true; gain = true
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.easeOut(duration: 0.45)) { gain = true }
        guard reward.leveledUp else {
            withAnimation(.easeInOut(duration: 0.8)) { bar = reward.after.fraction }
            return
        }
        withAnimation(.easeIn(duration: 0.7)) { bar = 1 }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) {
            popped = true
            shownLevel = reward.after.level
            banner = true
        }
        bar = 0
        try? await Task.sleep(for: .milliseconds(260))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { popped = false }
        withAnimation(.easeOut(duration: 0.6)) { bar = reward.after.fraction }
    }
}
