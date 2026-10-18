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
