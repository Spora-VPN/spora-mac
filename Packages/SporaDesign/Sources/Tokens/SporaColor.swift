import SwiftUI

/// Color tokens ported verbatim from the design system (`_ds/tokens/colors.css`,
/// locked direction "Instrument"). Light theme only for now — dark is designed
/// headroom, not shipped (the palette carries seeds: `pine900`, `sage200`).
///
/// Semantic split (the load-bearing rule): **ember/action** is the only orange
/// and means *act*, never error; **green** is the success/active family rooted
/// in the mark's green; **gold** is pending; **rust** is error. Orange never
/// touches an error surface.
public enum SporaColor {
    // ── base scales ──────────────────────────────────────────────
    public static let sage100 = Color(hex: 0xF6F8F4) // card
    public static let sage200 = Color(hex: 0xEFF2EE) // text/thumb on dark
    public static let sage300 = Color(hex: 0xD6DAD3) // app background
    public static let sage400 = Color(hex: 0xC2C7C1) // toggle track off
    public static let ink900 = Color(hex: 0x1D211D)  // primary text
    public static let ink600 = Color(hex: 0x494F49)  // muted text (AA on sage300)
    public static let pine800 = Color(hex: 0x333B36) // primary UI: buttons, toggle-on
    public static let pine900 = Color(hex: 0x272E29) // dark chrome
    public static let soil700 = Color(hex: 0x3E4A40) // mark arc (recolor B), quiet accent
    public static let green500 = Color(hex: 0x6C9044) // THE mark green — success root
    public static let green600 = Color(hex: 0x587536) // success dot on light (≥3:1)
    public static let green700 = Color(hex: 0x4E6B2F) // success text on light (≥4.5:1)
    public static let ember500 = Color(hex: 0xDB5F3D) // action orange — hero cards, big affirmative
    public static let ember050 = Color(hex: 0xFFF4EE) // titles on action
    public static let ember900 = Color(hex: 0x38180D) // micro-labels on action (AA)
    public static let gold500 = Color(hex: 0xDAC35B)  // pending fill
    public static let gold700 = Color(hex: 0x8A6D14)  // pending text/dot-ring
    public static let rust600 = Color(hex: 0xAC3322)  // error
    public static let rust800 = Color(hex: 0x7E2013)  // error emphasis

    // ── semantic aliases ─────────────────────────────────────────
    public static let surfaceBg = sage300
    public static let surfaceCard = sage100
    public static let surfaceNav = pine900
    public static let surfaceErrorTint = Color(hex: 0xAC3322, opacity: 0.08)

    public static let textPrimary = ink900
    public static let textMuted = ink600
    public static let textOnDark = sage200
    public static let textOnDarkMuted = Color(hex: 0x99A29A)

    public static let primary = pine800
    public static let action = ember500
    public static let onActionTitle = ember050
    public static let onActionMicro = ember900
    public static let success = green500
    public static let successDot = green600
    public static let successText = green700
    public static let pending = gold500
    public static let pendingText = gold700
    public static let error = rust600
    public static let errorStrong = rust800
    public static let waiting = ink600 // waiting-on-a-person is neutral, dashed

    public static let borderHairline = Color(hex: 0x1C201C, opacity: 0.15)
    public static let borderDivider = Color(hex: 0x1C201C, opacity: 0.10)
    public static let borderStrong = Color(hex: 0x1C201C, opacity: 0.35)
    public static let borderError = Color(hex: 0xAC3322, opacity: 0.5)
}

public extension Color {
    /// Hex initializer, sRGB, opaque unless `opacity` is given. Design tokens
    /// are authored as light-theme literals, so no dynamic (P3/dark) resolution.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
