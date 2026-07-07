import Foundation

/// Localized-string helpers. All user-facing strings resolve through the String
/// Catalog (`Localizable.xcstrings`) in locales en/ru/be, updated together
/// (CLAUDE.md rule). Micro-labels/statuses/buttons are ALREADY-UPPERCASE in the
/// catalog values. `SPORA` is hardcoded, never localized.
///
/// Keys are semantic (e.g. `error_generic`), so lookups go through
/// `NSLocalizedString` rather than source-string keying.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Formatted variant. Keys carry `%@` / `%lld` placeholders.
func Lf(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
