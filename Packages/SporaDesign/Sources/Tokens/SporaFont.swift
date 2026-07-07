import SwiftUI

/// Type system ported from `_ds/tokens/typography.css`: IBM Plex Sans (display +
/// body) and IBM Plex Mono (labels + data), chosen for full Cyrillic including
/// the be-specific Ў ў І і. Fonts are bundled in the app
/// (`App/Resources/Fonts`, registered via `ATSApplicationFontsPath`) — no
/// runtime fetches.
///
/// Weights are addressed by PostScript name so the exact face is selected
/// deterministically (IBM Plex groups every weight under one family name, but
/// `.weight()` matching on a many-face family is unreliable across releases).
public enum SporaFont {
    public enum Weight { case regular, medium, semibold, bold }

    static func sansName(_ w: Weight) -> String {
        switch w {
        case .regular: return "IBMPlexSans"
        case .medium: return "IBMPlexSans-Medm"
        case .semibold: return "IBMPlexSans-SmBld"
        case .bold: return "IBMPlexSans-Bold"
        }
    }

    static func monoName(_ w: Weight) -> String {
        switch w {
        case .regular: return "IBMPlexMono"
        case .medium, .semibold: return w == .medium ? "IBMPlexMono-Medm" : "IBMPlexMono-SmBld"
        case .bold: return "IBMPlexMono-SmBld"
        }
    }

    public static func sans(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom(sansName(weight), fixedSize: size)
    }

    public static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom(monoName(weight), fixedSize: size)
    }
}

/// A named type role: font plus its letter-spacing and (optional) extra line
/// spacing, so a single modifier reproduces a CSS `font` shorthand faithfully.
public struct SporaTextStyle: Sendable {
    public let font: Font
    public let tracking: CGFloat
    public let lineSpacing: CGFloat

    init(_ font: Font, tracking: CGFloat = 0, lineSpacing: CGFloat = 0) {
        self.font = font
        self.tracking = tracking
        self.lineSpacing = lineSpacing
    }
}

public extension SporaTextStyle {
    // display — hero titles, modal titles, big numbers
    static let display = SporaTextStyle(SporaFont.sans(26, .semibold), tracking: -0.5)
    static let displayLarge = SporaTextStyle(SporaFont.sans(30, .semibold), tracking: -0.5)
    // name — connection names, screen titles
    static let name = SporaTextStyle(SporaFont.sans(17, .semibold), tracking: -0.2)
    static let title = SporaTextStyle(SporaFont.sans(20, .semibold), tracking: -0.3)
    // body
    static let body = SporaTextStyle(SporaFont.sans(13.5), lineSpacing: 3.5)
    static let bodySmall = SporaTextStyle(SporaFont.sans(11.5), lineSpacing: 2)
    // micro label (mono, uppercase in source)
    static let micro = SporaTextStyle(SporaFont.mono(9.5, .medium), tracking: 1.4)
    // status (mono, uppercase in source)
    static let status = SporaTextStyle(SporaFont.mono(10, .medium), tracking: 0.6)
    // data — URLs, timestamps, amounts
    static let data = SporaTextStyle(SporaFont.mono(11), tracking: 0)
    // button label
    static let button = SporaTextStyle(SporaFont.sans(14, .semibold), tracking: 1)
    // wordmark (SPORA is always typeset, never drawn)
    static let wordmark = SporaTextStyle(SporaFont.sans(13, .bold), tracking: 2.4)
    // stat value
    static let stat = SporaTextStyle(SporaFont.sans(32, .semibold), tracking: -1)
}

private struct SporaTypeModifier: ViewModifier {
    let style: SporaTextStyle
    func body(content: Content) -> some View {
        content
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

public extension View {
    /// Apply a Spora type role (font + tracking + line spacing) in one call.
    func sporaType(_ style: SporaTextStyle) -> some View {
        modifier(SporaTypeModifier(style: style))
    }
}

public extension Text {
    /// Convenience for `Text(...).sporaType(...)` returning `some View`.
    func sporaType(_ style: SporaTextStyle) -> some View {
        self.font(style.font).tracking(style.tracking).lineSpacing(style.lineSpacing)
    }
}
