import SwiftUI

/// Underline-only text field (brand invariant §3.1). No box, no fill — a single
/// baseline rule that turns rust-red + 2px on error, with a diamond-marked
/// message. Ported from `_ds/components/forms/InputField.jsx`.
public struct InputField: View {
    private let label: String?
    private let placeholder: String
    @Binding private var text: String
    private let helper: String?
    private let error: String?

    public init(
        label: String? = nil,
        placeholder: String = "",
        text: Binding<String>,
        helper: String? = nil,
        error: String? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.helper = helper
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                Text(label).sporaType(.micro).foregroundStyle(SporaColor.textMuted)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(SporaFont.sans(21))
                .foregroundStyle(SporaColor.textPrimary)
                .tint(SporaColor.primary)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(error != nil ? SporaColor.error : SporaColor.textPrimary)
                        .frame(height: error != nil ? 2 : 1.5)
                }

            if let error {
                HStack(spacing: 7) {
                    StatusDot(.error, box: 7)
                    Text(error).font(SporaFont.sans(12)).foregroundStyle(SporaColor.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            } else if let helper {
                Text(helper)
                    .font(SporaFont.sans(11)).lineSpacing(2)
                    .foregroundStyle(SporaColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }
}
