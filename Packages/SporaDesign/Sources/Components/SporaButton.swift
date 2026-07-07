import SwiftUI

/// Buttons, ported from `_ds/components/core/Button.jsx`. Three variants:
/// `.primary` (pine, on-dark text — the neutral affirmative), `.action` (ember
/// hero — big affirmative, orange = act only), `.text` (quiet, micro-label).
/// Press feedback scales to 0.98.
public struct SporaButton: View {
    public enum Variant { case primary, action, text }

    private let title: String
    private let variant: Variant
    private let trailingArrow: Bool
    private let fullWidth: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        variant: Variant = .primary,
        trailingArrow: Bool = true,
        fullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.trailingArrow = variant == .text ? false : trailingArrow
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) { label }
            .buttonStyle(PressableButtonStyle())
    }

    @ViewBuilder private var label: some View {
        switch variant {
        case .text:
            Text(title)
                .sporaType(.micro)
                .foregroundStyle(SporaColor.textMuted)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
        case .action:
            row(
                bg: SporaColor.action,
                fg: SporaColor.onActionTitle,
                radius: SporaMetrics.radiusHero,
                padV: 17, padH: 20,
                font: SporaFont.sans(15, .semibold), tracking: 0.8,
                shadow: true
            )
        case .primary:
            row(
                bg: SporaColor.primary,
                fg: SporaColor.textOnDark,
                radius: SporaMetrics.radiusButton,
                padV: 15, padH: 18,
                font: SporaFont.sans(14, .semibold), tracking: 1,
                shadow: false
            )
        }
    }

    private func row(bg: Color, fg: Color, radius: CGFloat, padV: CGFloat, padH: CGFloat,
                     font: Font, tracking: CGFloat, shadow: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title).font(font).tracking(tracking)
            if fullWidth { Spacer(minLength: 0) }
            if trailingArrow { SporaIcon(.arrowRight, size: 18) }
        }
        .foregroundStyle(fg)
        .padding(.vertical, padV)
        .padding(.horizontal, padH)
        .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: radius))
        .modifier(HeroShadow(enabled: shadow))
        .contentShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// The one tinted shadow allowed on a hero surface (`--shadow-hero`).
struct HeroShadow: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.shadow(color: Color(hex: 0x96371E, opacity: 0.5), radius: 13, x: 0, y: 12)
        } else {
            content
        }
    }
}

/// Press = scale 0.98 (motion token), calm and short.
public struct PressableButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? SporaMotion.pressScale : 1)
            .animation(SporaMotion.easeQuick, value: configuration.isPressed)
    }
}
