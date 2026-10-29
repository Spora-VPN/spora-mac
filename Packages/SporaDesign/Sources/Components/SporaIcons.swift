import SwiftUI

/// Bespoke minimal stroke icon set (readme "ICONOGRAPHY"): 24-unit grid, round
/// caps/joins, geometry only — no icon font, no SF Symbols, no third-party set.
/// The design SVGs are line-only strokes with `stroke=currentColor`; they are
/// reproduced here as SwiftUI `Path`s so they tint with `foregroundStyle` and
/// stay crisp at any size. Direction is semantic: ↑ share (give), ↓ use
/// (receive).
public struct SporaIcon: View {
    public enum Glyph {
        case plus            // add / create
        case upload          // share again (↑ give)
        case external        // open in a new place
        case arrowRight      // affirmative / forward
        case trash           // delete
        case copy            // copy link (bespoke — rounded corner)
        case chevronRight
        case chevronLeft     // back out of a page
        case settings        // two sliders — settings
        case feedback        // speech bubble — send feedback
        case relays          // two ends reaching each other through a node
        case pulse           // pulse trace — telemetry
    }

    private let glyph: Glyph
    private let size: CGFloat
    private let strokeWidth: CGFloat

    public init(_ glyph: Glyph, size: CGFloat = 16, strokeWidth: CGFloat? = nil) {
        self.glyph = glyph
        self.size = size
        self.strokeWidth = strokeWidth ?? Self.defaultStroke(glyph)
    }

    private static func defaultStroke(_ g: Glyph) -> CGFloat {
        switch g {
        case .plus, .arrowRight, .chevronLeft: return 2
        default: return 1.8
        }
    }

    public var body: some View {
        // Bespoke copy glyph has a rounded corner (an arc); draw it explicitly.
        if case .copy = glyph {
            CopyGlyph(size: size, strokeWidth: strokeWidth)
        } else {
            SVGLineShape(pathData: Self.data(glyph))
                .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        }
    }

    private static func data(_ g: Glyph) -> String {
        switch g {
        case .plus: return "M12 5v14M5 12h14"
        case .upload: return "M12 15V4M8 7.5L12 3.5l4 4M5 13v6.5h14V13"
        case .external: return "M14 4h6v6M20 4L10 14M18 13v6H5V6h6"
        case .arrowRight: return "M5 12h14M12 5l7 7-7 7"
        case .trash: return "M5 7h14M10 7V5h4v2M7 7l.9 12.5h8.2L17 7"
        case .chevronRight: return "M9 6l6 6-6 6"
        case .chevronLeft: return "M14.5 6L8.5 12l6 6"
        case .settings:
            return "M4 7.5H6.5M11.5 7.5H20M11.5 7.5A2.5 2.5 0 1 1 6.5 7.5A2.5 2.5 0 1 1 11.5 7.5"
                + "M4 16.5H12.5M17.5 16.5H20M17.5 16.5A2.5 2.5 0 1 1 12.5 16.5A2.5 2.5 0 1 1 17.5 16.5"
        case .feedback:
            return "M20 6.5v7a2.5 2.5 0 0 1 -2.5 2.5H9.5L4 20V6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5z"
        case .relays:
            return "M14.5 7.5A2.5 2.5 0 1 1 9.5 7.5A2.5 2.5 0 1 1 14.5 7.5"
                + "M6.5 17A2 2 0 1 1 2.5 17A2 2 0 1 1 6.5 17"
                + "M21.5 17A2 2 0 1 1 17.5 17A2 2 0 1 1 21.5 17"
                + "M6.3 14.7L9.9 10.2M17.7 14.7L14.1 10.2"
        case .pulse: return "M3 12H7.5L10 6l4 12 2.5-6H21"
        case .copy: return ""
        }
    }
}

/// The copy glyph: a front sheet (rounded rect) with a back sheet whose
/// top-left corner is rounded — matches the design's
/// `<rect …/> <path d="M5 15V5 a2 2 0 0 1 2-2 h10">`.
private struct CopyGlyph: View {
    let size: CGFloat
    let strokeWidth: CGFloat
    var body: some View {
        let s = size / 24
        ZStack {
            RoundedRectangle(cornerRadius: 2 * s)
                .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                .frame(width: 11 * s, height: 11 * s)
                .offset(x: (14.5 - 12) * s, y: (14.5 - 12) * s)
            Path { p in
                p.move(to: CGPoint(x: 5 * s, y: 15 * s))
                p.addLine(to: CGPoint(x: 5 * s, y: 7 * s))
                p.addQuadCurve(to: CGPoint(x: 7 * s, y: 3 * s),
                               control: CGPoint(x: 5 * s, y: 3 * s))
                p.addLine(to: CGPoint(x: 17 * s, y: 3 * s))
            }
            .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

/// Minimal SVG path shape supporting the commands used by the icon set:
/// M/m L/l H/h V/v Z/z and circular arcs A/a (rx = ry, no rotation), absolute
/// and relative. Curves are not needed by any icon (the copy glyph's rounded
/// corner lives in `CopyGlyph`). Coordinates are in a 24-unit viewBox and
/// scaled to the shape's rect.
struct SVGLineShape: Shape {
    let pathData: String
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / viewBox
        let sy = rect.height / viewBox
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        let tokens = tokenize(pathData)
        var i = 0
        var cmd: Character = "M"

        func nextNum() -> CGFloat? {
            guard i < tokens.count, case let .number(v) = tokens[i] else { return nil }
            i += 1
            return CGFloat(v)
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        while i < tokens.count {
            if case let .command(c) = tokens[i] { cmd = c; i += 1 }
            switch cmd {
            case "M", "m":
                guard let x = nextNum(), let y = nextNum() else { i += 1; continue }
                current = cmd == "m" ? CGPoint(x: current.x + x * sx, y: current.y + y * sy) : pt(x, y)
                path.move(to: current); start = current
                cmd = (cmd == "m") ? "l" : "L"
            case "L", "l":
                guard let x = nextNum(), let y = nextNum() else { i += 1; continue }
                current = cmd == "l" ? CGPoint(x: current.x + x * sx, y: current.y + y * sy) : pt(x, y)
                path.addLine(to: current)
            case "H", "h":
                guard let x = nextNum() else { i += 1; continue }
                current = cmd == "h" ? CGPoint(x: current.x + x * sx, y: current.y) : CGPoint(x: x * sx, y: current.y)
                path.addLine(to: current)
            case "V", "v":
                guard let y = nextNum() else { i += 1; continue }
                current = cmd == "v" ? CGPoint(x: current.x, y: current.y + y * sy) : CGPoint(x: current.x, y: y * sy)
                path.addLine(to: current)
            case "A", "a":
                // rx ry rotation large-arc sweep x y; rx = ry and no rotation
                // in this icon set, so the arc is circular.
                guard let r = nextNum(), nextNum() != nil, nextNum() != nil,
                      let large = nextNum(), let sweep = nextNum(),
                      let x = nextNum(), let y = nextNum() else { i += 1; continue }
                let from = CGPoint(x: current.x / sx, y: current.y / sy)
                let to = cmd == "a" ? CGPoint(x: from.x + x, y: from.y + y) : CGPoint(x: x, y: y)
                for p in Self.arcPoints(from: from, to: to, radius: r, large: large != 0, sweep: sweep != 0) {
                    path.addLine(to: pt(p.x, p.y))
                }
                current = pt(to.x, to.y)
            case "Z", "z":
                path.closeSubpath(); current = start
            default:
                i += 1
            }
        }
        return path
    }

    /// Points along a circular SVG arc from `from` to `to` (both in viewBox
    /// units), ending at `to` — the SVG 1.1 F.6.5 endpoint-to-center
    /// conversion, sampled finely enough to read as a curve at icon sizes.
    static func arcPoints(from: CGPoint, to: CGPoint, radius: CGFloat, large: Bool, sweep: Bool) -> [CGPoint] {
        let hx = (from.x - to.x) / 2, hy = (from.y - to.y) / 2
        guard radius > 0, hx != 0 || hy != 0 else { return [to] }
        let r = max(radius, (hx * hx + hy * hy).squareRoot())
        let num = max(0, r * r - hx * hx - hy * hy)
        let coef = (large == sweep ? -1 : 1) * (num / (hx * hx + hy * hy)).squareRoot()
        let cx = coef * hy + (from.x + to.x) / 2
        let cy = -coef * hx + (from.y + to.y) / 2
        let start = atan2(from.y - cy, from.x - cx)
        var delta = atan2(to.y - cy, to.x - cx) - start
        if sweep, delta < 0 { delta += 2 * .pi }
        if !sweep, delta > 0 { delta -= 2 * .pi }
        let steps = max(4, Int((abs(delta) / (2 * .pi) * 48).rounded(.up)))
        var points = (1..<steps).map { k -> CGPoint in
            let t = start + delta * CGFloat(k) / CGFloat(steps)
            return CGPoint(x: cx + r * cos(t), y: cy + r * sin(t))
        }
        points.append(to)
        return points
    }

    private enum Token { case command(Character); case number(Double) }

    private func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isLetter {
                tokens.append(.command(c)); i += 1
            } else if c == "-" || c == "." || c.isNumber {
                var s = ""
                if c == "-" { s.append(c); i += 1 }
                var seenDot = false
                while i < chars.count, chars[i].isNumber || (chars[i] == "." && !seenDot) {
                    if chars[i] == "." { seenDot = true }
                    s.append(chars[i]); i += 1
                }
                if let v = Double(s) { tokens.append(.number(v)) }
            } else {
                i += 1 // separators: space, comma
            }
        }
        return tokens
    }
}
