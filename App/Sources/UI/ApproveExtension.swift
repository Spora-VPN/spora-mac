import SwiftUI
import SporaDesign

/// The direct build's first connect: macOS holds the tunnel's system
/// extension until the user allows it in System Settings. The guide stays up
/// while macOS waits and goes by itself once the extension is allowed; the
/// connect then carries on to the VPN-configuration prompt.
struct ApproveExtensionSheet: View {
    @EnvironmentObject var controller: AppController

    /// Where the switch is: Login Items & Extensions since macOS 15, a note
    /// under Privacy & Security before.
    private var stepsKey: String {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
            ? "extension_approve_steps" : "extension_approve_steps_legacy"
    }

    var body: some View {
        SheetBody {
            MicroLabel(L("extension_approve_header"))
            Text(L("extension_approve_title")).sporaType(.display).foregroundStyle(SporaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text(L("extension_approve_message")).sporaType(.body).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text(L(stepsKey)).sporaType(.body).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            VStack(spacing: 2) {
                SporaButton(L("extension_approve_open"), variant: .primary) {
                    controller.openExtensionSettings()
                }
                SporaButton(L("cancel"), variant: .text) {
                    controller.cancelExtensionApproval()
                }
            }
            .padding(.top, 24)
        }
    }
}
