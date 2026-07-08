#if DEBUG
import AppKit
import SwiftUI
import SporaKit

/// Debug-only IPC for the feedback harness (`scripts/dev.sh`) — the macOS
/// counterpart to Android's `DebugStateReceiver` + `emu.sh`. Driven through the
/// `spora-debug://` URL scheme (no entitlement, works unsigned). The command
/// vocabulary is kept identical to Android's so screenshot matrices stay
/// portable. Compiled only into DEBUG builds; routes straight into the real
/// `AppModel`.
///
///   spora-debug://seed?shares=<n>&uses=<n>
///   spora-debug://share-starting|started|failed|stopped?id=<id>[&url=][&err=]
///   spora-debug://connect-connecting|connected|failed|disconnected?id=<id>[&err=]
///   spora-debug://select?id=<id>   ·   reset   ·   shot?name=<n>   ·   quit
@MainActor
enum DebugController {
    static var artifactsDir: URL = {
        if let env = ProcessInfo.processInfo.environment["SPORA_ARTIFACTS_DIR"] {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("artifacts", isDirectory: true)
    }()

    // Belarusian sample names (design canvas parity).
    private static let shareNames = ["Мамін тэлефон", "Тэлефон Алесі", "Працоўны ноўтбук", "Стары планшэт", "Backup"]
    private static let useNames = ["Дом Даны", "Кватэра ў Берліне"]
    private static let debugIdentity = Data("debug".utf8) // intentionally invalid → exercises real error path

    static func handle(_ url: URL, model: AppModel, controller: AppController) {
        guard url.scheme == "spora-debug" else { return }
        let cmd = url.host ?? ""
        let q = queryItems(url)
        NSLog("[spora-debug] cmd=\(cmd) args=\(q)")

        switch cmd {
        case "shot": shoot(name: q["name"] ?? "shot")
        case "popover": shootPopover(name: q["name"] ?? "popover", model: model, controller: controller)
        case "quit": NSApp.terminate(nil)
        case "reset": controller.loadPersisted()
        case "seed":
            controller.persistenceSuppressed = true
            seed(model, shares: Int(q["shares"] ?? "0") ?? 0, uses: Int(q["uses"] ?? "0") ?? 0)
        case "create-share": controller.beginCreateShare() // exercise the real share() flow
        case "connect-url": if let u = q["url"] { controller.connectToURL(u) } // real tunnel
        case "icon-preview": iconPreview()
        case "connect-self": // connect to this app's own freshly-created share (loopback)
            if let url = model.shares.compactMap({ model.shareURL($0.id) }).first {
                controller.connectToURL(url)
            }
        case "select": model.selectedId = q["id"]
        case "share-starting": if let id = q["id"] { model.shareStarting(id) }
        case "share-started":
            if let id = q["id"] {
                model.shareStarted(id, handle: 9000, url: q["url"] ?? AppController.syntheticURL(id))
            }
        case "share-failed": if let id = q["id"] { model.shareFailed(id, error: SporaError(token: q["err"])) }
        case "share-stopped": if let id = q["id"] { model.shareStopped(id) }
        case "connect-connecting": model.connectConnecting(q["id"])
        case "connect-connected":
            model.connectConnecting(q["id"]); model.connectConnected()
        case "connect-failed": model.connectFailed(SporaError(token: q["err"]), id: q["id"])
        case "connect-disconnected": model.connectDisconnected()
        default: NSLog("[spora-debug] unknown cmd: \(cmd)")
        }
    }

    private static func seed(_ model: AppModel, shares: Int, uses: Int) {
        var shareConns: [ShareConnection] = []
        for i in 0..<shares {
            let id = "debug-share-\(i + 1)"
            shareConns.append(ShareConnection(
                id: id,
                label: shareNames[i % shareNames.count],
                identity: debugIdentity,
                createdAt: Date().addingTimeInterval(-Double(i + 1) * 30 * 86400)
            ))
        }
        var useConns: [UseConnection] = []
        for i in 0..<uses {
            useConns.append(UseConnection(
                id: "debug-use-\(i + 1)",
                label: useNames[i % useNames.count],
                url: "https://spora.to/s/debug\(i + 1)",
                createdAt: Date().addingTimeInterval(-Double(i + 1) * 20 * 86400)
            ))
        }
        model.setConnections(shares: shareConns, uses: useConns)
        for c in shareConns { model.registerShareURL(c.id, AppController.syntheticURL(c.id)) }
        model.selectedId = shareConns.first?.id ?? useConns.first?.id
    }

    /// Render the four menu-bar icon states (scaled up, on white) so the tray
    /// icon can be inspected without capturing the system menu bar.
    private static func iconPreview() {
        let states: [(String, MenuBarState)] = [("offline", .offline), ("active", .active), ("pending", .pending), ("error", .error)]
        let scale: CGFloat = 6, cellW: CGFloat = 200, cellH: CGFloat = 70
        let w = cellW * CGFloat(states.count)
        let img = NSImage(size: NSSize(width: w, height: cellH))
        img.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: cellH).fill()
        for (i, entry) in states.enumerated() {
            let icon = MenuBarLabel.icon(for: entry.1)
            icon.isTemplate = false // draw literal black rather than template tint
            let iw = icon.size.width * scale, ih = icon.size.height * scale
            icon.draw(in: NSRect(x: CGFloat(i) * cellW + (cellW - iw) / 2, y: (cellH - ih) / 2, width: iw, height: ih))
        }
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
        try? png.write(to: artifactsDir.appendingPathComponent("icon-preview.png"))
        NSLog("[spora-debug] icon-preview written (states: \(states.map(\.0)))")
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return [:] }
        var out: [String: String] = [:]
        for it in items { out[it.name] = it.value?.removingPercentEncoding ?? it.value }
        return out
    }

    /// Render the main window in-process (no Screen Recording permission) and
    /// write it as a PNG to `artifacts/`. Runs after a short delay so layout and
    /// animations settle.
    static func shoot(name: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let window = mainWindow(),
                  let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                NSLog("[spora-debug] shot: no window / bitmap")
                return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            let dir = artifactsDir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = dir.appendingPathComponent("\(name).png")
            do {
                try png.write(to: out)
                NSLog("[spora-debug] shot: wrote \(out.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
            } catch {
                NSLog("[spora-debug] shot: write failed: \(error)")
            }
        }
    }

    /// Render the menu-bar popover into an offscreen host window and capture it
    /// (the MenuBarExtra popover can't be opened programmatically). Verifies the
    /// 1d/2e layout deterministically.
    static func shootPopover(name: String, model: AppModel, controller: AppController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let root = MenuBarPopover()
                .environmentObject(model)
                .environmentObject(controller)
                .environment(\.colorScheme, .light)
            let hosting = NSHostingView(rootView: AnyView(root))
            hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 700)
            let fitting = hosting.fittingSize
            let size = NSSize(width: 280, height: max(fitting.height, 120))
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -2000, y: -2000), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            let dir = artifactsDir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = dir.appendingPathComponent("\(name).png")
            try? png.write(to: out)
            NSLog("[spora-debug] popover: wrote \(out.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
            window.close()
        }
    }

    static func mainWindow() -> NSWindow? {
        NSApp.windows.first { win in
            win.isVisible && win.contentView != nil && win.styleMask.contains(.titled)
                && !String(describing: type(of: win)).contains("StatusBar")
        } ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil }
    }
}
#endif
