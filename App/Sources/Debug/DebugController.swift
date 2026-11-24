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
///   spora-debug://settings?page=list|relays|telemetry   ·   settings-close
///   spora-debug://relays?spora=1|0&own=<host:port>[,…]&tokens=1,0,…  (in memory)
///   spora-debug://make-failed?err=NO_RELAYS   ·   make-new-link?id=   ·   delete[?id=]   ·   toggle[?id=]
///   spora-debug://feedback   ·   telemetry-required   ·   export-report   ·   telemetry?on=1|0
///   spora-debug://sheet?name=relay-add|relay-edit|relay-remove&index=<i>
///   spora-debug://sheet?name=approve-extension[&closed=1]  (closed: the window is closed first)
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
    // Not a share: toggling a seeded share on calls the real startShare() and
    // fails, which conveniently exercises the error path.
    private static let debugShare = Data("debug".utf8)

    static func handle(_ url: URL, model: AppModel, controller: AppController) {
        guard url.scheme == "spora-debug" else { return }
        let cmd = url.host ?? ""
        let q = queryItems(url)
        SporaLog.d("DebugController", "cmd=\(cmd) args=\(q)")

        switch cmd {
        case "shot": shoot(name: q["name"] ?? "shot")
        case "popover": shootPopover(name: q["name"] ?? "popover", model: model, controller: controller)
        case "quit": NSApp.terminate(nil)
        case "reset":
            controller.loadPersisted()
            controller.service.reloadRelays()
            controller.settingsPages = []
            controller.dismissFlow()
            controller.sheet = nil
        case "seed":
            controller.persistenceSuppressed = true
            seed(model, shares: Int(q["shares"] ?? "0") ?? 0, uses: Int(q["uses"] ?? "0") ?? 0)
        case "create-share": controller.beginCreateShare() // exercise the real share() flow
        case "connect-url": if let u = q["url"] { controller.connectToURL(u) } // real tunnel
        case "icon-preview": iconPreview()
        case "gen-appicon": genAppIcon()
        case "connect-self": // connect to this app's own freshly-created share (loopback)
            if let url = model.shares.compactMap({ model.shareURL($0.id) }).first {
                controller.connectToURL(url)
            }
        case "select": if let id = q["id"] { controller.select(id) }
        case "settings":
            switch q["page"] {
            case "relays": controller.settingsPages = [.list, .relays]
            case "telemetry": controller.settingsPages = [.list, .telemetry]
            default: controller.openSettings()
            }
        case "settings-close": controller.settingsPages = []
        case "relays":
            let own = (q["own"] ?? "").split(separator: ",").map(String.init)
            let tokens = (q["tokens"] ?? "").split(separator: ",").map { $0 == "1" }
            controller.service.seedRelays(RelaySettings(
                useSpora: q["spora"] != "0",
                own: own.enumerated().map { i, e in
                    OwnRelay(endpoint: e, token: tokens.indices.contains(i) && tokens[i] ? "debug-token" : nil)
                }
            ))
        case "make-failed": controller.flow = .createShare(.failed(SporaError(token: q["err"])))
        case "make-new-link": if let id = q["id"] { controller.makeNewLink(id) }
        case "toggle": // the real toggle of a saved connection (startShare / the tunnel)
            if let id = q["id"] ?? model.selectedId {
                if model.shares.contains(where: { $0.id == id }) { controller.toggleShare(id) } else { controller.toggleUse(id) }
            }
        case "delete": // a real (persisted) connection, as the detail's DELETE does
            if let id = q["id"] ?? model.selectedId { controller.select(id); controller.deleteSelected() }
        case "feedback": controller.openFeedback()
        case "export-report": // the bug report alone, without the share picker
            Task.detached { _ = await BugReport.prepare(note: "harness") }
        case "telemetry": // the real upload switch
            Task { _ = await controller.service.setUploadEnabled(q["on"] == "1") }
        case "telemetry-required": controller.showTelemetryRequired()
        case "sheet":
            let index = Int(q["index"] ?? "0") ?? 0
            switch q["name"] {
            case "relay-add": controller.sheet = .relayEditor(index: nil)
            case "relay-edit": controller.sheet = .relayEditor(index: index)
            case "relay-remove": controller.sheet = .removeRelay(index: index)
            case "connect": controller.sheet = .saveConnection(prefillURL: nil)
            case "approve-extension":
                if q["closed"] == "1" {
                    // As a connect from the menu bar finds it: no window
                    // (this URL opened one, if there was none)
                    // Not mainWindow(), which settles for any window
                    let window = {
                        NSApp.windows.first {
                            $0.isVisible && $0.styleMask.contains(.titled)
                                && !String(describing: type(of: $0)).contains("StatusBar")
                        }
                    }
                    // Once this URL is dealt with: the window that takes it
                    // is brought back if closed here
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        window()?.close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            let before = window() == nil ? "closed" : "open"
                            controller.showApprovalGuide()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                SporaLog.d("DebugController", "approval guide: window \(before), then "
                                    + "\(window() == nil ? "closed" : "open"), "
                                    + "sheet \(window()?.attachedSheet == nil ? "none" : "up")")
                            }
                        }
                    }
                } else {
                    controller.showApprovalGuide()
                }
            default: controller.sheet = nil
            }
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
        default: SporaLog.w("DebugController", "unknown cmd: \(cmd)")
        }
    }

    private static func seed(_ model: AppModel, shares: Int, uses: Int) {
        var shareConns: [ShareConnection] = []
        for i in 0..<shares {
            let id = "debug-share-\(i + 1)"
            shareConns.append(ShareConnection(
                id: id,
                label: shareNames[i % shareNames.count],
                share: debugShare,
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

    /// The center of the mark's circle (its arc, fitted from logo-icon.svg's
    /// path: (35.9, 50.3) in the 73×102 viewBox), as fractions of the logo
    /// image, y from the top.
    private static let markCircleCenter = CGPoint(x: 35.9 / 73, y: 50.3 / 102)

    /// Generate the macOS app-icon PNGs (the 2-color spore mark on a sage
    /// rounded-rect) at exact pixel sizes, into artifacts/appicon/.
    private static func genAppIcon() {
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        let bg = NSColor(srgbRed: 0xD6 / 255.0, green: 0xDA / 255.0, blue: 0xD3 / 255.0, alpha: 1)
        let mark = NSImage(named: "LogoIcon")
        let dir = artifactsDir.appendingPathComponent("appicon")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for px in sizes {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let s = CGFloat(px)
            let inset = s * 0.06
            let side = s - 2 * inset
            let card = NSRect(x: inset, y: inset, width: side, height: side)
            NSBezierPath(roundedRect: card, xRadius: side * 0.2237, yRadius: side * 0.2237).addClip()
            bg.setFill(); card.fill()
            if let mark {
                // The mark itself (not its SVG canvas, which has empty space
                // below it), 64% of the card tall, with its circle's center on
                // the card's center: the visual center. The tail pulls the
                // bounding box up, so bbox-centering sits the circle low.
                let source = mark.drawnBounds() ?? NSRect(origin: .zero, size: mark.size)
                let k = side * 0.64 / max(source.height, 1)
                let circle = NSPoint(x: markCircleCenter.x * mark.size.width,
                                     y: (1 - markCircleCenter.y) * mark.size.height)
                mark.draw(in: NSRect(x: s / 2 - k * (circle.x - source.minX),
                                     y: s / 2 - k * (circle.y - source.minY),
                                     width: k * source.width, height: k * source.height),
                          from: source, operation: .sourceOver, fraction: 1)
            }
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("icon_\(px).png"))
            }
        }
        SporaLog.d("DebugController", "app icon PNGs written to \(dir.path)")
    }

    /// Render the four menu-bar icon states (scaled up, on white) so the tray
    /// icon can be inspected without capturing the system menu bar.
    private static func iconPreview() {
        let states: [(String, MenuBarState)] = [("offline", .offline), ("active", .active), ("pending", .pending), ("error", .error)]
        let scale: CGFloat = 6, cellW: CGFloat = 220, cellH: CGFloat = 130
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
        menuBarPreview(states.map(\.1))
        SporaLog.d("DebugController", "icon-preview written (states: \(states.map(\.0)))")
    }

    /// The states at their real size (2x pixels) on a 24pt menu-bar strip,
    /// beside clock text in the menu bar's font, to judge the icon's size
    /// without capturing the system menu bar.
    private static func menuBarPreview(_ states: [MenuBarState]) {
        let w: CGFloat = 330, h: CGFloat = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(h * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        var x: CGFloat = 12
        for state in states {
            let icon = MenuBarLabel.icon(for: state)
            icon.isTemplate = false
            icon.draw(in: NSRect(x: x, y: (h - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            x += icon.size.width + 22
        }
        let clock = NSAttributedString(string: "Wed 29 Oct  16:54", attributes: [
            .font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: NSColor.black])
        clock.draw(at: NSPoint(x: x + 6, y: (h - clock.size().height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?
            .write(to: artifactsDir.appendingPathComponent("menubar-preview.png"))
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
                SporaLog.d("DebugController", "shot: no window / bitmap")
                return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            let dir = artifactsDir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // A sheet is its own window: captured next to the window's shot
            if let sheet = window.attachedSheet?.contentView,
               let sheetRep = sheet.bitmapImageRepForCachingDisplay(in: sheet.bounds) {
                sheet.cacheDisplay(in: sheet.bounds, to: sheetRep)
                try? sheetRep.representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("\(name)-sheet.png"))
            }
            let out = dir.appendingPathComponent("\(name).png")
            do {
                try png.write(to: out)
                SporaLog.d("DebugController", "shot: wrote \(out.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
            } catch {
                SporaLog.d("DebugController", "shot: write failed: \(error)")
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
            SporaLog.d("DebugController", "popover: wrote \(out.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
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
