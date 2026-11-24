import Foundation
import NetworkExtension

// The system-extension packaging of the packet tunnel (ADR-002 D2): the same
// `PacketTunnelProvider` as the app extension, started by sysextd instead of
// the extension point. NetworkExtension instantiates the provider class that
// Info.plist names when a tunnel starts.
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
