import SwiftUI
import CoreText

// MARK: - Charte Oculot : couleurs et typographie

extension Color {
    /// Color from a 0xRRGGBB literal.
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Palette {
    static let night   = Color(rgb: 0x0D0D0F)   // fond du panneau
    static let card    = Color(rgb: 0x18181B)   // cartes
    static let raised  = Color(rgb: 0x222226)   // survol, sélection
    static let hair    = Color.white.opacity(0.07)
    static let cream   = Color(rgb: 0xF6F1E7)   // texte principal
    static let sand    = Color(rgb: 0xA8A196)   // texte secondaire
    static let dust    = Color(rgb: 0x6B665E)   // texte discret
    static let tomate  = Color(rgb: 0xFF5B37)   // accent Oculot
    static let beurre  = Color(rgb: 0xFFD65C)   // à surveiller
    static let menthe  = Color(rgb: 0x52D6A0)   // tout va bien
    static let alerte  = Color(rgb: 0xFF4757)   // panne
    static let lilas   = Color(rgb: 0xB8A5FF)   // Claude Code
    static let ciel    = Color(rgb: 0x7CC4FF)   // agenda
    static let rose    = Color(rgb: 0xFF77A9)   // Instagram
}

enum Typo {
    static let displayFamily = "Bricolage Grotesque"

    /// Registers the bundled Bricolage Grotesque (OFL) for this process.
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom(displayFamily, size: size).weight(weight)
    }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
