import SwiftUI

/// Spacing, corner-radius and motion tokens (`_ds/tokens/spacing.css`,
/// `motion.css`). The radii scale is the sharper "Instrument" scale (10 for
/// cards/buttons, not v1's 24/12).
public enum SporaMetrics {
    // spacing rhythm
    public static let space1: CGFloat = 4
    public static let space2: CGFloat = 8
    public static let space3: CGFloat = 12
    public static let space4: CGFloat = 16
    public static let space5: CGFloat = 20
    public static let space6: CGFloat = 24

    // corner radii
    public static let radiusHero: CGFloat = 16   // hero action cards, accept button
    public static let radiusCard: CGFloat = 10   // list items, grouped cards
    public static let radiusChip: CGFloat = 6
    public static let radiusTag: CGFloat = 4
    public static let radiusNav: CGFloat = 20
    public static let radiusButton: CGFloat = 10
    public static let radiusToggle: CGFloat = 3  // squared toggle track
    public static let radiusThumb: CGFloat = 1   // squared toggle thumb
    public static let radiusRow: CGFloat = 7     // sidebar / popover row highlight

    // status dot geometry (shape coding)
    public static let dotSize: CGFloat = 7
    public static let dotRingSize: CGFloat = 8

    // hit target (a11y invariant)
    public static let hitTarget: CGFloat = 48

    // window / popover geometry (committed direction 1b + 1d)
    public static let windowWidth: CGFloat = 880
    public static let windowHeight: CGFloat = 620
    public static let sidebarWidth: CGFloat = 248
    public static let popoverWidth: CGFloat = 280
}

/// Motion tokens — calm and short; one easing.
public enum SporaMotion {
    public static let quick: Double = 0.15      // toggle thumb, press
    public static let standard: Double = 0.22   // state fades, transitions
    public static let pressScale: CGFloat = 0.98

    /// cubic-bezier(0.2, 0.8, 0.2, 1)
    public static let easeStandard = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: standard)
    public static let easeQuick = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: quick)
}
