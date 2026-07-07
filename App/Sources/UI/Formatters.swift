import Foundation

enum Fmt {
    /// Session duration as HH:MM:SS (mono/tabular in the UI).
    static func elapsed(since start: Date, now: Date = Date()) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    static func date(_ date: Date) -> String {
        guard date != .distantPast else { return "—" }
        return mediumDate.string(from: date)
    }

    /// A stable barcode seed derived from a connection id.
    static func seed(_ id: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in id.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }
}
