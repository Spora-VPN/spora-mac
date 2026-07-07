import SwiftUI

/// The squared toggle — rectangular track, square thumb (brand invariant §3.1).
/// 40×22 visual inside a 48pt effective hit target. Thumb slides 150ms.
///
/// Ported from `_ds/components/forms/SporaToggle.jsx`: on → track `pine800`,
/// thumb `sage200`; off → track `sage400`, thumb `surfaceCard` with a hairline.
public struct SporaToggle: View {
    @Binding private var isOn: Bool
    private let isEnabled: Bool
    private let accessibilityLabel: String?
    private let action: (() -> Void)?

    /// Bound form — flips `isOn` on tap.
    public init(isOn: Binding<Bool>, enabled: Bool = true, accessibilityLabel: String? = nil) {
        self._isOn = isOn
        self.isEnabled = enabled
        self.accessibilityLabel = accessibilityLabel
        self.action = nil
    }

    /// Intent form — reports the requested value without owning it (the store
    /// decides whether the transition actually happens, e.g. toggling a share
    /// on/off while starting = cancel). `on` reflects current visual state.
    public init(on: Bool, enabled: Bool = true, accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self._isOn = .constant(on)
        self.isEnabled = enabled
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button {
            guard isEnabled else { return }
            if let action {
                action()
            } else {
                withAnimation(SporaMotion.easeQuick) { isOn.toggle() }
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: SporaMetrics.radiusToggle)
                    .fill(isOn ? SporaColor.primary : SporaColor.sage400)
                    .frame(width: 40, height: 22)
                RoundedRectangle(cornerRadius: SporaMetrics.radiusThumb)
                    .fill(isOn ? SporaColor.sage200 : SporaColor.surfaceCard)
                    .frame(width: 16, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: SporaMetrics.radiusThumb)
                            .strokeBorder(isOn ? Color.clear : Color(hex: 0x1C201C, opacity: 0.12), lineWidth: 1)
                    )
                    .padding(.horizontal, 3)
            }
            .frame(width: 40, height: 22)
            .animation(SporaMotion.easeQuick, value: isOn)
            // 48pt effective target around the 40×22 visual.
            .padding(13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-13)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityRepresentation {
            Toggle(accessibilityLabel ?? "", isOn: .constant(isOn)).disabled(!isEnabled)
        }
    }
}
