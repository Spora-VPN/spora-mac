import Foundation
import NetworkExtension
import SporaKit

// The system-extension packaging of the packet tunnel (ADR-002 D2): the same
// `PacketTunnelProvider` as the app extension, started by sysextd instead of
// the extension point. NetworkExtension instantiates the provider class that
// Info.plist names when a tunnel starts.
//
// This process is root, so its records and log are out of the app's reach:
// it hands them to the app over its Mach service (`DiagnosticsHandover`).
// First of all: what is in its directories before any provider exists was
// left by an earlier process, and is what the hand-over takes for finished.
autoreleasepool {
    DiagnosticsHandover.serve()
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
