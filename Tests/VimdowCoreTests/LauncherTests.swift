import Foundation
import Testing
@testable import VimdowCore

private func app(_ name: String, aliases: [String] = []) -> LauncherItem {
    LauncherItem(id: "/Applications/\(name).app", name: name, aliases: aliases, kind: .application)
}

private func pane(_ name: String, id: String, aliases: [String] = []) -> LauncherItem {
    LauncherItem(id: id, name: name, aliases: aliases, kind: .settingsPane)
}

private let catalog = [
    app("System Settings"), app("Google Chrome"), app("Chrome Remote Desktop"),
    pane("Wi\u{2011}Fi", id: "com.apple.wifi-settings-extension"), app("Activity Monitor"),
    app("Terminal"), app("Visual Studio Code"), app("Xcode"),
]

private func names(_ query: String, in items: [LauncherItem] = catalog,
                   history: LauncherHistory = LauncherHistory(), limit: Int = 8) -> [String] {
    LauncherMatcher.rank(items, query: query, history: history, limit: limit).map(\.name)
}

@Test func launcherNormalizationFoldsCaseWidthDiacriticsSeparatorsAndHangul() {
    #expect(LauncherHistory.normalize(" Wi\u{2011}Fi ") == "wi fi")
    #expect(LauncherHistory.normalize("Privacy & Security") == "privacy security")
    #expect(LauncherHistory.normalize("Café") == "cafe")
    #expect(LauncherHistory.normalize("ＧＯＯＧＬＥ") == "google")
    #expect(LauncherHistory.normalize("한글".decomposedStringWithCanonicalMapping) == "한글")
    #expect(LauncherHistory.normalize("a.b/c-d") == "a b c d")
    #expect(LauncherHistory.normalize("   ") == "")
    #expect(LauncherMatcher.words("Touch ID & Password") == ["touch", "id", "password"])
}

@Test func launcherTiersRankExactThenPrefixThenLaterWordThenInitialsThenSubstring() {
    #expect(names("terminal").first == "Terminal")
    #expect(names("Terminal ") == ["Terminal"])
    #expect(names("chrome") == ["Chrome Remote Desktop", "Google Chrome"])
    #expect(names("gc").first == "Google Chrome")
    #expect(names("sysset").first == "System Settings")
    #expect(names("sys set").first == "System Settings")
    #expect(names("wifi").first == "Wi\u{2011}Fi")
    #expect(names("wi-fi").first == "Wi\u{2011}Fi")
    #expect(names("actmon").first == "Activity Monitor")
    #expect(names("code") == ["Visual Studio Code", "Xcode"])
    #expect(names("xoe").isEmpty) // Subsequences do not match.
    #expect(names("zzz").isEmpty)
}

@Test func launcherAliasesMatchAtTheirOwnTier() {
    let battery = pane("Battery", id: "com.apple.Battery-Settings.extension", aliases: ["Energy", "PowerPreferences"])
    let items = catalog + [battery]
    #expect(names("energy", in: items) == ["Battery"])
    #expect(names("power", in: items) == ["Battery"])
    #expect(names("battery", in: items) == ["Battery"])
}

@Test func launcherTieBreaksUseHistoryCountThenLengthThenName() {
    let items = [app("Note Taker"), app("Notion"), app("Notes"), app("Nota")]
    #expect(names("not", in: items) == ["Nota", "Notes", "Notion", "Note Taker"])
    var history = LauncherHistory()
    history.record(query: "x", itemID: app("Notion").id)
    history.record(query: "y", itemID: app("Notion").id)
    #expect(names("not", in: items, history: history) == ["Notion", "Nota", "Notes", "Note Taker"])
    #expect(history.useCount(of: app("Notion").id) == 2)
}

@Test func launcherPreferredItemLeadsEvenWithoutMatching() {
    let items = [app("Ghostty"), app("Terminal")]
    var history = LauncherHistory()
    history.record(query: "Term", itemID: app("Ghostty").id)
    #expect(names("term", in: items, history: history) == ["Ghostty", "Terminal"])
    #expect(names("gho", in: items, history: history) == ["Ghostty"])
    history.record(query: "term", itemID: "/Applications/Removed.app")
    #expect(names("term", in: items, history: history) == ["Terminal"])
}

@Test func launcherEmptyQueryAndLimit() {
    var history = LauncherHistory()
    history.record(query: "", itemID: app("Terminal").id)
    #expect(names("", history: history).isEmpty)
    #expect(names("  \n", history: history).isEmpty)
    #expect(history.preferredItemID(for: "") == nil)
    let many = (1...12).map { app("App \($0)") }
    #expect(names("app", in: many).count == 8)
    #expect(names("app", in: many, limit: 3).count == 3)
    #expect(names("app", in: many, limit: 0).isEmpty)
}

@Test func launcherHistoryIsBoundedLRUNormalizedAndCodable() throws {
    var history = LauncherHistory()
    for index in 1...LauncherHistory.limit {
        history.record(query: "q\(index)", itemID: "item\(index)")
    }
    history.record(query: "q1", itemID: "item1") // Refreshed, so q2 is now the oldest.
    history.record(query: "q501", itemID: "item501")
    #expect(history.entries.count == LauncherHistory.limit)
    #expect(history.preferredItemID(for: "q2") == nil)
    #expect(history.preferredItemID(for: "q1") == "item1")
    #expect(history.preferredItemID(for: "Q501") == "item501")
    #expect(history.useCount(of: "item1") == 2)
    #expect(history.useCount(of: "item2") == 0) // Pruned with its only query.
    history.record(query: " Wi\u{2011}Fi ", itemID: "wifi")
    #expect(history.preferredItemID(for: "wi fi") == "wifi")
    #expect(history.preferredItemID(for: "WIFI") == nil)
    let data = try JSONEncoder().encode(history)
    #expect(try JSONDecoder().decode(LauncherHistory.self, from: data) == history)
}
