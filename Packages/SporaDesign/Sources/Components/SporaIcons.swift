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
        case .plus, .arrowRight: return 2
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

/// Minimal SVG path shape supporting the line commands used by the icon set:
/// M/m L/l H/h V/v Z/z (absolute + relative). Arcs/curves are not needed by any
/// icon (the one rounded corner lives in `CopyGlyph`). Coordinates are in a
/// 24-unit viewBox and scaled to the shape's rect.
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
            case "Z", "z":
                path.closeSubpath(); current = start
            default:
                i += 1
            }
        }
        return path
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
