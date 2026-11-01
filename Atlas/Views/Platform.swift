import SwiftUI

enum Platform {
    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif

    #if os(tvOS)
    static let isTV = true
    /// Harita etiketleri gibi sabit boyutlu çizimler TV'de uzaktan okunacak kadar büyütülür.
    static let drawScale: CGFloat = 2
    #else
    static let isTV = false
    static let drawScale: CGFloat = 1
    #endif

    /// Platformun bir metin stili için varsayılan boyutu (özel yazı tipleri bu boyutla kullanılır).
    static func textSize(_ style: Font.TextStyle) -> CGFloat {
        #if os(macOS)
        let map: [Font.TextStyle: NSFont.TextStyle] = [.largeTitle: .largeTitle, .title: .title1, .title2: .title2,
                                                        .title3: .title3, .headline: .headline, .body: .body]
        return NSFont.preferredFont(forTextStyle: map[style] ?? .body).pointSize
        #else
        var map: [Font.TextStyle: UIFont.TextStyle] = [.title: .title1, .title2: .title2, .title3: .title3,
                                                       .headline: .headline, .body: .body]
        #if os(iOS)
        map[.largeTitle] = .largeTitle
        #endif
        // tvOS'ta largeTitle yok; başlık stiliyle aynı boyutta kullanılır.
        let ui = map[style] ?? (style == .largeTitle ? .title1 : .body)
        // Dinamik Yazı ölçeklemesini `relativeTo:` yapar; burada varsayılan boyut alınır.
        return UIFont.preferredFont(forTextStyle: ui, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        #endif
    }
}

extension View {
    /// Sayfa (sheet) boyutu macOS'ta sabit genişlikte, iPhone'da tam ekran olur.
    @ViewBuilder
    func sheetWidth(_ width: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width)
        #else
        frame(maxWidth: .infinity)
        #endif
    }
}

extension View {
    /// Enter / Esc kısayolları; Apple TV'de klavye kısayolu yoktur.
    @ViewBuilder
    func defaultActionShortcut() -> some View {
        #if os(tvOS)
        self
        #else
        keyboardShortcut(.defaultAction)
        #endif
    }

    @ViewBuilder
    func cancelActionShortcut() -> some View {
        #if os(tvOS)
        self
        #else
        keyboardShortcut(.cancelAction)
        #endif
    }
}
