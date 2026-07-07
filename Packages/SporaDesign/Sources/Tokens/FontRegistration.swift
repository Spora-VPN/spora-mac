import CoreText
import Foundation

public extension SporaDesign {
    /// Register the bundled IBM Plex TTFs with the process's font manager.
    /// `ATSApplicationFontsPath` usually handles this at launch, but this is a
    /// backstop that also works when resources are flattened into `Resources/`
    /// rather than `Resources/Fonts/`. Idempotent — "already registered" errors
    /// are ignored, so the app and the tunnel extension can both call it.
    static func registerFonts() {
        var urls: [URL] = []
        let bundle = Bundle.main
        for subdir in ["Fonts", nil] {
            if let found = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: subdir) {
                urls.append(contentsOf: found)
            }
        }
        // De-dup by last path component (a font may resolve under both lookups).
        var seen = Set<String>()
        for url in urls where seen.insert(url.lastPathComponent).inserted {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
