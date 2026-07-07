import SwiftUI

/// Hero action card — a tab's primary call to action. Orange = act (and nothing
/// else). Ported from `_ds/components/surfaces/ActionCard.jsx`.
///
/// `.primary` is the filled ember hero (eyebrow + display title + subtitle +
/// circle-arrow); `.secondary` is the outlined quieter entry (used for the
/// "have a link?" second action). The circle-arrow points −45° and never
/// overlaps the subtitle.
public struct ActionCard: View {
    public enum Variant { case primary, secondary }

    private let eyebrow: String
    private let title: String
    private let subtitle: String?
    private let variant: Variant
    private let action: () -> Void

    public init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        variant: Variant = .primary,
        action: @escaping () -> Void
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.variant = variant
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            variant == .primary ? AnyView(primary) : AnyView(secondary)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var primary: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                Text(eyebrow)
                    .font(SporaFont.mono(10, .medium)).tracking(1.6)
                    .foregroundStyle(SporaColor.onActionMicro)
                Text(title)
                    .sporaType(.display)
                    .foregroundStyle(SporaColor.onActionTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 12) {
                if let subtitle {
                    Text(subtitle)
                        .font(SporaFont.sans(12.5)).lineSpacing(3)
                        .foregroundStyle(SporaColor.onActionTitle.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                circleArrow(color: SporaColor.onActionTitle)
            }
        }
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20))
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(SporaColor.action, in: RoundedRectangle(cornerRadius: SporaMetrics.radiusHero))
        .modifier(HeroShadow(enabled: true))
        .contentShape(RoundedRectangle(cornerRadius: SporaMetrics.radiusHero))
    }

    private var secondary: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow).sporaType(.micro).foregroundStyle(SporaColor.textMuted)
                Text(title)
                    .font(SporaFont.sans(19, .semibold)).tracking(-0.2)
                    .foregroundStyle(SporaColor.textPrimary)
                if let subtitle {
                    Text(subtitle).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            circleArrow(color: SporaColor.textPrimary)
        }
        .padding(.vertical, 15).padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SporaColor.sage100.opacity(0.45), in: RoundedRectangle(cornerRadius: SporaMetrics.radiusHero))
        .overlay(
            RoundedRectangle(cornerRadius: SporaMetrics.radiusHero)
                .strokeBorder(SporaColor.borderStrong, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: SporaMetrics.radiusHero))
    }

    private func circleArrow(color: Color) -> some View {
        SporaIcon(.arrowRight, size: 16)
            .foregroundStyle(color)
            .rotationEffect(.degrees(-45))
            .frame(width: 40, height: 40)
            .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
    }
}
