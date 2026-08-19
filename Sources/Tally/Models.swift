import SwiftUI

/// How a chunk of time counts toward your day.
enum Category: String, Codable, CaseIterable, Identifiable {
    case work
    case distraction
    case neutral
    /// At the machine but not touching it. Never assigned by a rule — the
    /// tracker produces it directly from lack of input.
    case idle

    var id: String { rawValue }

    /// The categories a person can actually put something in. `idle` is
    /// excluded: you can't classify an app as "away".
    static var assignable: [Category] { [.work, .distraction, .neutral] }

    var label: String {
        switch self {
        case .work: return "Focus"
        case .distraction: return "Drain"
        case .neutral: return "Other"
        case .idle: return "Idle"
        }
    }

    var color: Color {
        switch self {
        case .work: return Color(red: 0.18, green: 0.80, blue: 0.55)
        case .distraction: return Color(red: 0.98, green: 0.42, blue: 0.38)
        case .neutral: return Color(white: 0.46)
        case .idle: return Color(red: 0.36, green: 0.40, blue: 0.50)
        }
    }

    var symbol: String {
        switch self {
        case .work: return "target"
        case .distraction: return "wave.3.right"
        case .neutral: return "circle.dashed"
        case .idle: return "moon.zzz"
        }
    }
}

/// The sentinel session written while you're away from the keyboard.
enum Idle {
    static let bundleID = "xyz.polify.tally.idle"
    static let name = "Idle"
}

/// A contiguous stretch of time spent in one place.
///
/// Deliberately stores only *raw* observations — never the category. Category is
/// derived from the current rules at read time, so re-classifying something
/// retroactively fixes every day you've ever recorded.
struct Session: Codable, Identifiable {
    var start: Date
    var end: Date
    var app: String
    var bundleID: String
    var host: String?

    var id: String { "\(bundleID)|\(host ?? "")|\(start.timeIntervalSince1970)" }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// What to show the user: the site if we know it, otherwise the app.
    var displayName: String { host ?? app }

    /// The key that rules match against.
    var ruleKey: RuleKey {
        if let host { return .host(host) }
        return .app(bundleID)
    }
}

enum RuleKey: Hashable {
    case app(String)
    case host(String)

    /// Flat string form, so a key can live in rules.json.
    var storageKey: String {
        switch self {
        case .app(let bundleID): return "app:\(bundleID)"
        case .host(let host): return "host:\(host)"
        }
    }

    init?(storageKey: String) {
        if let value = storageKey.stripping("app:") { self = .app(value) }
        else if let value = storageKey.stripping("host:") { self = .host(value) }
        else { return nil }
    }
}

private extension String {
    func stripping(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        let value = String(dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }
}

/// Formats a duration the way a human would say it out loud.
func formatDuration(_ t: TimeInterval, style: DurationStyle = .short) -> String {
    let total = Int(t.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60

    switch style {
    case .short:
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    case .compact:
        if h > 0 { return "\(h)h\(String(format: "%02d", m))" }
        return "\(m)m"
    }
}

enum DurationStyle { case short, compact }
