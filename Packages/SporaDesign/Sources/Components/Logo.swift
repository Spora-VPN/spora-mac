import SwiftUI

/// The spore mark + `SPORA` wordmark lockup. `SPORA` is always typeset (never
/// drawn) and hardcoded — never localized (CLAUDE.md rule). Assets live in the
/// app's catalog and resolve from the main bundle.
///
/// Mark variants: `.ink` uses the 2-color recolor-B mark on light surfaces;
/// `.monoLight`/`.monoInk` are the template silhouettes for dark chrome / menu
/// bar. Icon centering matters — `LogoMark` uses the tight-bbox `logo-mark-b`
/// for inline lockups; `LogoIcon` uses the circle-centered mark for box-centered
/// placements (empty state, app icon).
public struct SporaMark: View {
    public enum Variant { case ink, monoInk, monoLight }
    private let variant: Variant
    private let height: CGFloat
    private let tint: Color?

    public init(_ variant: Variant = .ink, height: CGFloat = 20, tint: Color? = nil) {
        self.variant = variant
        self.height = height
        self.tint = tint
    }

    public var body: some View {
        image
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .modifier(TemplateTint(variant: variant, tint: tint))
    }

    private var image: Image {
        switch variant {
        case .ink: return Image("LogoMark")
        case .monoInk: return Image("LogoMonoInk").renderingMode(.template)
        case .monoLight: return Image("LogoMonoLight").renderingMode(.template)
        }
    }
}

private struct TemplateTint: ViewModifier {
    let variant: SporaMark.Variant
    let tint: Color?
    func body(content: Content) -> some View {
        switch variant {
        case .ink:
            content
        case .monoInk:
            content.foregroundStyle(tint ?? SporaColor.textPrimary)
        case .monoLight:
            content.foregroundStyle(tint ?? SporaColor.textOnDark)
        }
    }
}

/// The circle-centered mark (`logo-icon`) for box-centered placements.
public struct SporaLogoIcon: View {
    private let height: CGFloat
    public init(height: CGFloat = 46) { self.height = height }
    public var body: some View {
        Image("LogoIcon").resizable().scaledToFit().frame(height: height)
    }
}

/// Mark + `SPORA` wordmark, horizontally.
public struct SporaLockup: View {
    private let markVariant: SporaMark.Variant
    private let markHeight: CGFloat
    private let wordmark: SporaTextStyle
    private let color: Color

    public init(
        mark: SporaMark.Variant = .ink,
        markHeight: CGFloat = 20,
        wordmark: SporaTextStyle = .wordmark,
        color: Color = SporaColor.textPrimary
    ) {
        self.markVariant = mark
        self.markHeight = markHeight
        self.wordmark = wordmark
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 9) {
            SporaMark(markVariant, height: markHeight, tint: color)
            Text("SPORA")
                .sporaType(wordmark)
                .foregroundStyle(color)
        }
    }
}
