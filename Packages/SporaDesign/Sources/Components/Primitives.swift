import SwiftUI

/// Uppercase mono micro-label (section headers, eyebrows). Text is authored
/// ALREADY-UPPERCASE at the call site (ru/be caps are intentional).
public struct MicroLabel: View {
    private let text: String
    private let color: Color
    public init(_ text: String, color: Color = SporaColor.textMuted) {
        self.text = text
        self.color = color
    }
    public var body: some View {
        Text(text).sporaType(.micro).foregroundStyle(color)
    }
}

/// A shape-coded status line: optional dot + status/arrow text + optional mono
/// meta (a duration or count). Mono by default; error lines pass `mono: false`
/// for sentence-case sans. The arrow (↑ share / ↓ use) is part of `text`.
public struct StatusLine: View {
    private let dot: StatusShape?
    private let text: String
    private let color: Color
    private let meta: String?
    private let mono: Bool

    public init(
        dot: StatusShape?,
        text: String,
        color: Color,
        meta: String? = nil,
        mono: Bool = true
    ) {
        self.dot = dot
        self.text = text
        self.color = color
        self.meta = meta
        self.mono = mono
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let dot { StatusDot(dot) }
            if mono {
                Text(text).sporaType(.status).foregroundStyle(color)
                    .lineLimit(1).truncationMode(.tail)
            } else {
                Text(text).font(SporaFont.sans(11.5)).lineSpacing(1.5).foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let meta {
                Text(meta).sporaType(.data).foregroundStyle(SporaColor.textMuted)
                    .padding(.leading, 2)
            }
        }
    }
}

/// Standard card surface: solid `surfaceCard`, 1px hairline, card radius. No
/// shadow — shadows exist only on the hero card and nav (readme "Cards").
public struct SporaCard<Content: View>: View {
    private let content: Content
    private let padding: EdgeInsets?
    public init(padding: EdgeInsets? = nil, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    public var body: some View {
        Group {
            if let padding { content.padding(padding) } else { content }
        }
        .background(SporaColor.surfaceCard, in: RoundedRectangle(cornerRadius: SporaMetrics.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SporaMetrics.radiusCard)
                .strokeBorder(SporaColor.borderHairline, lineWidth: 1)
        )
    }
}

public extension View {
    /// Wrap in the standard hairline card surface.
    func sporaCard() -> some View {
        background(SporaColor.surfaceCard, in: RoundedRectangle(cornerRadius: SporaMetrics.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: SporaMetrics.radiusCard)
                    .strokeBorder(SporaColor.borderHairline, lineWidth: 1)
            )
    }
}
