import SwiftUI
import SporaKit
import SporaDesign

/// Bridges SporaKit's role-independent `DisplayState` to the design system's
/// shape/color vocabulary. Kept in the app layer because it joins domain
/// semantics (SporaKit) with presentation (SporaDesign).
extension DisplayState {
    var shape: StatusShape {
        switch self {
        case .inactive: return .inactive
        case .pending: return .pending
        case .active: return .active
        case .error: return .error
        case .waiting: return .waiting
        }
    }

    var statusColor: Color {
        switch self {
        case .active: return SporaColor.successText
        case .pending: return SporaColor.pendingText
        case .error: return SporaColor.error
        case .waiting: return SporaColor.waiting
        case .inactive: return SporaColor.textMuted
        }
    }
}

extension Role {
    /// Directional arrow embedded in status text: ↑ share (give), ↓ use (receive).
    var arrow: String { self == .share ? "↑" : "↓" }
}

/// Uppercase a name in the current locale for status tags (ru/be caps are wide
/// and intentional). Guillemets are added only in sentence prose, per token.
func upper(_ s: String) -> String { s.uppercased() }
