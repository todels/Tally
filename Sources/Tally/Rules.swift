import Foundation

/// The user's classification of apps and sites. Everything unknown is `.neutral`
/// until they say otherwise — the app never guesses silently about new things.
struct Rules: Codable {
    var apps: [String: Category] = [:]
    var hosts: [String: Category] = [:]

    /// The one thing you most want a number for, shown as its own headline
    /// figure rather than buried in the list. Defaults to Figma.
    var pinned: String? = nil
    var pinnedName: String? = nil

    static let figmaBundleID = "com.figma.Desktop"

    /// Falls back to Figma when unset or unreadable, so the headline always
    /// shows something meaningful.
    var pinnedKey: RuleKey {
        pinned.flatMap { RuleKey(storageKey: $0) } ?? .app(Self.figmaBundleID)
    }

    var pinnedLabel: String {
        if let pinnedName, !pinnedName.isEmpty { return pinnedName }
        if case .host(let host) = pinnedKey { return host }
        return "Figma"
    }

    static let `default` = Rules(
        apps: [
            "com.figma.Desktop": .work,
            "com.apple.dt.Xcode": .work,
            "com.microsoft.VSCode": .work,
            "com.todesktop.230313mzl4w4u92": .work,   // Cursor
            "com.apple.Terminal": .work,
            "com.googlecode.iterm2": .work,
            "com.mitchellh.ghostty": .work,
            "com.linear": .work,
            "notion.id": .work,
            "com.adobe.AfterEffects": .work,
            "com.adobe.illustrator": .work,
            "com.adobe.Photoshop": .work,
            "com.bohemiancoding.sketch3": .work,
            // Comms count as work — this is how the work actually happens.
            "ru.keepcoder.Telegram": .work,
            "com.tinyspeck.slackmacgap": .work,
            "com.hnc.Discord": .work,
            "com.anthropic.claudefordesktop": .work,
            "com.spotify.client": .neutral,
            "com.apple.MobileSMS": .neutral,
            "com.apple.mail": .neutral,
        ],
        hosts: [
            // Drains
            "youtube.com": .distraction,
            "x.com": .distraction,
            "twitter.com": .distraction,
            "reddit.com": .distraction,
            "instagram.com": .distraction,
            "tiktok.com": .distraction,
            "netflix.com": .distraction,
            "twitch.tv": .distraction,
            "facebook.com": .distraction,
            "linkedin.com": .distraction,
            "news.ycombinator.com": .distraction,
            // Focus
            "figma.com": .work,
            "github.com": .work,
            "linear.app": .work,
            "notion.so": .work,
            "claude.ai": .work,
            // Exact hosts, not google.com as a whole — plain search stays
            // unclassified rather than being quietly counted as work.
            "meet.google.com": .work,
            "gemini.google.com": .work,
            // Reference gathering counts as work. Suffix matching means this
            // also covers se.pinterest.com, uk.pinterest.com and friends.
            "pinterest.com": .work,
            "dribbble.com": .work,
            "behance.net": .work,
            "framer.com": .work,
            "vercel.com": .work,
        ]
    )

    /// Longest-suffix match, so a rule on `youtube.com` also covers
    /// `music.youtube.com` without needing its own entry.
    func category(for key: RuleKey) -> Category {
        switch key {
        case .app(let bundleID):
            return apps[bundleID] ?? .neutral
        case .host(let host):
            if let exact = hosts[host] { return exact }
            let matches = hosts.keys
                .filter { host.hasSuffix("." + $0) }
                .sorted { $0.count > $1.count }
            if let best = matches.first { return hosts[best]! }
            return .neutral
        }
    }

    mutating func set(_ category: Category, for key: RuleKey) {
        switch key {
        case .app(let bundleID): apps[bundleID] = category
        case .host(let host): hosts[host] = category
        }
    }

    mutating func pin(_ key: RuleKey, named name: String) {
        pinned = key.storageKey
        pinnedName = name
    }
}

/// Loads and saves rules as plain JSON on disk, so you can hand-edit them.
final class RulesStore: ObservableObject {
    @Published var rules: Rules {
        didSet { save() }
    }

    private let url = Store.directory.appendingPathComponent("rules.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Rules.self, from: data) {
            rules = decoded
        } else {
            rules = .default
        }
    }

    func category(for key: RuleKey) -> Category {
        // Idle isn't rule-driven — the tracker produces it from lack of input.
        if case .app(let bundleID) = key, bundleID == Idle.bundleID { return .idle }
        return rules.category(for: key)
    }

    func set(_ category: Category, for key: RuleKey) {
        rules.set(category, for: key)
    }

    func pin(_ key: RuleKey, named name: String) {
        rules.pin(key, named: name)
    }

    var pinnedKey: RuleKey { rules.pinnedKey }
    var pinnedLabel: String { rules.pinnedLabel }

    func isPinned(_ key: RuleKey) -> Bool { rules.pinnedKey == key }

    private func save() {
        Store.ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(rules).write(to: url, options: .atomic)
    }
}
