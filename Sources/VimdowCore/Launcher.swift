import Foundation

/// An application or System Settings pane that the launcher can open.
public struct LauncherItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case application, settingsPane
    }

    /// The bundle path of an application or the bundle identifier of a pane.
    public let id: String
    /// The localized display name.
    public let name: String
    /// Other names that find the item, such as the English name on a localized system.
    public let aliases: [String]
    public let kind: Kind

    public init(id: String, name: String, aliases: [String] = [], kind: Kind) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.kind = kind
    }
}

/// The item chosen for each query, so that the same query ranks it first next time.
public struct LauncherHistory: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let query: String
        public let itemID: String
        public let date: Date

        public init(query: String, itemID: String, date: Date) {
            self.query = query
            self.itemID = itemID
            self.date = date
        }
    }

    /// The number of queries remembered; the least recently used are forgotten first.
    public static let limit = 500

    /// Oldest first, one entry per normalized query.
    public private(set) var entries: [Entry] = []
    /// Launches per item among the remembered queries.
    public private(set) var useCounts: [String: Int] = [:]

    public init() {}

    public mutating func record(query: String, itemID: String, at date: Date = .now) {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { return }
        entries.removeAll { $0.query == normalized }
        entries.append(Entry(query: normalized, itemID: itemID, date: date))
        useCounts[itemID, default: 0] += 1
        guard entries.count > Self.limit else { return }
        entries.removeFirst(entries.count - Self.limit)
        let referenced = Set(entries.map(\.itemID))
        useCounts = useCounts.filter { referenced.contains($0.key) }
    }

    public func preferredItemID(for query: String) -> String? {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { return nil }
        return entries.last { $0.query == normalized }?.itemID
    }

    public func useCount(of itemID: String) -> Int { useCounts[itemID] ?? 0 }

    /// The words of `text` joined by single spaces; see `LauncherMatcher.words`.
    public static func normalize(_ text: String) -> String {
        LauncherMatcher.words(text).joined(separator: " ")
    }
}

/// Ranks launcher items for a query the way a launcher is expected to: exact names
/// first, then prefixes, word prefixes, initials, and finally substrings.
public enum LauncherMatcher {
    /// Lowercase words without diacritics or width variants. Every character that is
    /// neither a letter nor a digit separates words, so "Wi‑Fi" becomes ["wi", "fi"].
    public static func words(_ text: String) -> [String] {
        // Folding can leave Hangul as separate jamo; recomposing afterwards makes
        // decomposed and precomposed Korean compare equal.
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .precomposedStringWithCanonicalMapping
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    public static func rank(_ items: [LauncherItem], query: String, history: LauncherHistory,
                            limit: Int = 8) -> [LauncherItem] {
        let queryWords = words(query)
        guard !queryWords.isEmpty, limit > 0 else { return [] }
        let spaced = queryWords.joined(separator: " ")
        let compact = queryWords.joined()
        var matches: [(item: LauncherItem, tier: Int)] = []
        for item in items {
            let tiers = ([item.name] + item.aliases).compactMap { tier(of: words($0), spaced: spaced, compact: compact) }
            if let best = tiers.min() { matches.append((item, best)) }
        }
        matches.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            let lhsUses = history.useCount(of: lhs.item.id), rhsUses = history.useCount(of: rhs.item.id)
            if lhsUses != rhsUses { return lhsUses > rhsUses }
            if lhs.item.name.count != rhs.item.name.count { return lhs.item.name.count < rhs.item.name.count }
            return lhs.item.name < rhs.item.name
        }
        var ranked = matches.map(\.item)
        if let preferredID = history.preferredItemID(for: query),
           let preferred = items.first(where: { $0.id == preferredID }) {
            ranked.removeAll { $0.id == preferredID }
            ranked.insert(preferred, at: 0)
        }
        return Array(ranked.prefix(limit))
    }

    /// Lower is better; nil means no match.
    private static func tier(of words: [String], spaced: String, compact: String) -> Int? {
        guard !words.isEmpty else { return nil }
        let joined = words.joined(separator: " ")
        if joined == spaced { return 0 }
        if joined.hasPrefix(spaced) { return 1 }
        if words.indices.dropFirst().contains(where: { words[$0...].joined(separator: " ").hasPrefix(spaced) }) {
            return 2
        }
        if spansWordPrefixes(compact[...], words: words[...]) { return 3 }
        if joined.contains(spaced) { return 4 }
        return nil
    }

    /// True when `query` splits into non-empty prefixes of consecutive leading words,
    /// as "gc" does for "google chrome" and "wifi" does for "wi fi".
    private static func spansWordPrefixes(_ query: Substring, words: ArraySlice<String>) -> Bool {
        if query.isEmpty { return true }
        guard let word = words.first else { return false }
        var wordIndex = word.startIndex
        var queryIndex = query.startIndex
        while wordIndex < word.endIndex, queryIndex < query.endIndex, word[wordIndex] == query[queryIndex] {
            wordIndex = word.index(after: wordIndex)
            queryIndex = query.index(after: queryIndex)
            if spansWordPrefixes(query[queryIndex...], words: words.dropFirst()) { return true }
        }
        return false
    }
}
