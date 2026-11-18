import SwiftUI

/// Semantic palette mirrored from design/prototype/shared.css (light/dark
/// pairs). Values are the prototype contract's; the dark variant activates
/// through the matched color scheme so both themes always ship together
/// (DESIGN.md 不变式 4).
enum Palette {
    private static func pair(_ light: String, _ dark: String) -> Color {
        Color(light: Color(hex: light), dark: Color(hex: dark))
    }

    static let bg = pair("#FAF8F5", "#16120F")
    static let surface = pair("#FFFFFF", "#1F1A16")
    static let raised = pair("#F3EFE9", "#29231E")
    static let line = pair("#DED9D2", "#493E35")
    static let ink = pair("#201B16", "#F1ECE5")
    static let mute = pair("#665D54", "#BEB3A7")
    static let faint = pair("#746B62", "#AEA295")
    static let accent = pair("#A6472E", "#EDAC91")
    static let accentSoft = pair("#F7E8E1", "#38251D")
    static let brand = pair("#D97757", "#E08A6B")
    static let ok = pair("#237346", "#92DCB0")
    static let okSoft = pair("#EAF4ED", "#1E3025")
    static let warn = pair("#94540A", "#F0BE6E")
    static let warnSoft = pair("#FFF3DF", "#342B1C")
    static let danger = pair("#B3261E", "#FFA59E")
    static let dangerSoft = pair("#FFF0EE", "#3A211E")

    /// Light-theme primary buttons use white text; dark-theme ones use the
    /// light ink (shared.css .btn.primary dark override).
    static let onAccent = pair("#FFFFFF", "#201B16")

    static let radiusControl: CGFloat = 8
    static let radiusCard: CGFloat = 12
    static let radiusDialog: CGFloat = 16
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        let clean = hex.dropFirst()
        Scanner(string: String(clean)).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { traits in
            traits.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}

/// Type scale from the prototype: page titles 28, section heads 20, body 16,
/// secondary 14, metadata 12.
enum TypeScale {
    static let page = Font.system(size: 28, weight: .semibold)
    static let section = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 15)
    static let secondary = Font.system(size: 14)
    static let meta = Font.system(size: 12)
    static let display = Font.system(size: 34, weight: .semibold)
}
