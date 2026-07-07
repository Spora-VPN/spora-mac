import SwiftUI

/// The barcode strip — Spora's only data-viz motif (readme "Data-viz =
/// barcode"). Deterministic from a seed, 3 quantized bar heights (30/60/100%).
/// Do not introduce charts or sparklines; this is the one ornament.
///
/// PRNG and quantization ported exactly from
/// `_ds/components/data/Barcode.jsx` (mulberry32) so a given seed renders the
/// identical strip as the design canvas.
public struct Barcode: View {
    private let bars: Int
    private let seed: UInt32
    private let height: CGFloat
    private let color: Color
    private let opacity: Double
    private let barWidth: CGFloat
    private let gap: CGFloat

    public init(
        seed: UInt32,
        bars: Int = 84,
        height: CGFloat = 18,
        color: Color = SporaColor.successDot,
        opacity: Double = 0.75,
        barWidth: CGFloat = 2,
        gap: CGFloat = 2
    ) {
        self.bars = bars
        self.seed = seed
        self.height = height
        self.color = color
        self.opacity = opacity
        self.barWidth = barWidth
        self.gap = gap
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: barWidth, height: h)
            }
        }
        .opacity(opacity)
        .frame(height: height, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityHidden(true)
    }

    private var heights: [CGFloat] {
        var rng = Mulberry32(seed: seed)
        return (0..<bars).map { _ in
            let v = rng.next()
            if v > 0.82 { return height }
            if v > 0.5 { return (height * 0.6).rounded() }
            return (height * 0.3).rounded()
        }
    }
}

/// mulberry32 — the seeded PRNG the design system uses for the barcode. 32-bit
/// wrapping arithmetic mirrors JS `Math.imul` / `>>>`.
struct Mulberry32 {
    private var t: UInt32
    init(seed: UInt32) { t = seed }

    mutating func next() -> Double {
        t = t &+ 0x6d2b_79f5
        var r = (t ^ (t >> 15)) &* (1 | t)
        r ^= r &+ ((r ^ (r >> 7)) &* (61 | r))
        return Double(r ^ (r >> 14)) / 4_294_967_296.0
    }
}
