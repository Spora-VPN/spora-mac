import SwiftUI

/// Shape-coded status marker. Status must be legible **without color** (a11y
/// invariant, readme "Status shapes"): ● filled circle = active · ○ ring =
/// pending · ◆ diamond = error · ◌ dashed ring = waiting-on-a-person · inactive
/// draws nothing but reserves the box so rows stay aligned.
public enum StatusShape: Sendable {
    case active, pending, error, waiting, inactive
}

public struct StatusDot: View {
    private let shape: StatusShape
    private let box: CGFloat

    /// - Parameter box: the square bounding size that keeps rows aligned (8 by
    ///   default — matches the design's dot/ring geometry).
    public init(_ shape: StatusShape, box: CGFloat = 8) {
        self.shape = shape
        self.box = box
    }

    public var body: some View {
        Group {
            switch shape {
            case .active:
                Circle().fill(SporaColor.successDot).frame(width: 7, height: 7)
            case .pending:
                Circle().strokeBorder(SporaColor.pendingText, lineWidth: 1.8)
                    .frame(width: 8, height: 8)
            case .error:
                RoundedRectangle(cornerRadius: 1)
                    .fill(SporaColor.error)
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(45))
            case .waiting:
                Circle()
                    .strokeBorder(
                        SporaColor.waiting,
                        style: StrokeStyle(lineWidth: 1.5, dash: [2, 1.6])
                    )
                    .frame(width: 8, height: 8)
            case .inactive:
                Color.clear
            }
        }
        .frame(width: box, height: box)
    }
}
