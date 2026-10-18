import Foundation

/// Search that understands how a Windows user thinks.
///
/// Every query token is expanded through a synonym table — so typing
/// "task manager", "print screen", "ctrl c" or "alt tab" finds the Mac
/// equivalent. On top of that, each item's Windows equivalent is indexed,
/// so literal Windows shortcut searches hit directly.
enum SearchEngine {

    /// term -> acceptable alternatives (matched against the item index)
    private static let synonyms: [String: [String]] = [
        // keys
        "ctrl":    ["ctrl", "control", "command", "⌘", "⌃"],
        "cmd":     ["cmd", "command", "⌘"],
        "command": ["command", "cmd", "⌘"],
        "alt":     ["alt", "option", "⌥"],
        "option":  ["option", "alt", "⌥"],
        "win":     ["win", "windows", "command", "⌘"],
        "shift":   ["shift", "⇧"],
        "esc":     ["esc", "escape"],
        "escape":  ["escape", "esc"],
        "del":     ["del", "delete", "esc"],
        "backspace": ["backspace", "delete"],
        "enter":   ["enter", "return"],
        "prtsc":   ["prtsc", "screenshot", "print screen"],
        "printscreen": ["printscreen", "screenshot"],
        "fn":      ["fn", "globe", "function"],
        // concepts
        "screen":   ["screen", "screenshot", "display"],
        "snip":     ["snip", "screenshot", "snipping"],
        "task":     ["task", "force quit", "activity monitor", "task manager"],
        "manager":  ["manager", "activity monitor", "force quit"],
        "explorer": ["explorer", "finder"],
        "panel":    ["panel", "settings"],
        "settings": ["settings", "system settings", "preferences", "control panel"],
        "trash":    ["trash", "recycle bin"],
        "bin":      ["bin", "trash", "recycle"],
        "lock":     ["lock", "lock screen"],
        "quit":     ["quit", "force quit", "close", "exit"],
        "kill":     ["kill", "force quit"],
        "close":    ["close", "quit", "window"],
        "exit":     ["exit", "quit", "close"],
        "maximize": ["maximize", "full screen", "zoom", "green button"],
        "minimize": ["minimize", "minimise", "dock"],
        "snap":     ["snap", "tile", "split"],
        "tile":     ["tile", "split", "snap"],
        "desktop":  ["desktop", "spaces", "mission control", "show desktop"],
        "taskbar":  ["taskbar", "dock"],
        "start":    ["start", "spotlight", "launchpad", "menu"],
        "search":   ["search", "spotlight", "find"],
        "preview":  ["preview", "quick look"],
        "properties": ["properties", "get info"],
        "rename":   ["rename"],
        "clipboard":["clipboard", "copy", "paste"],
        "emoji":    ["emoji", "emoticon"],
        "refresh":  ["refresh", "reload"],
        "incognito":["incognito", "private"],
        "zip":      ["zip", "compress", "archive"],
        "uninstall":["uninstall", "trash", "remove", "delete"],
        "shutdown": ["shutdown", "shut down", "power", "restart"],
        "reboot":   ["reboot", "restart"],
        "language": ["language", "input", "layout", "keyboard"],
        "record":   ["record", "recording", "video"],
        "sign":     ["sign", "signature", "log", "pdf"],
        "volume":   ["volume", "sound", "audio"],
        "scroll":   ["scroll", "wheel", "natural"],
        "mouse":    ["mouse", "right-click", "click", "trackpad"],
        "touch":    ["touch", "trackpad", "gesture"],
        "gesture":  ["gesture", "swipe", "trackpad", "pinch"],
        "window":   ["window", "windows", "macwindow"],
        "virus":    ["virus", "security", "lock"],
        "wifi":     ["wifi", "wi-fi", "network", "control center"],
        "bluetooth":["bluetooth", "control center"],
        "notification": ["notification", "widgets"],
        "widgets":  ["widgets", "notification"],
    ]

    /// Multi-word phrases checked before per-token expansion.
    private static let phrases: [String: [String]] = [
        "task manager":  ["force quit", "activity monitor"],
        "alt tab":       ["switch apps", "⌘", "tab"],
        "alt f4":        ["quit"],
        "control panel": ["system settings"],
        "print screen":  ["screenshot"],
        "prt scr":       ["screenshot"],
        "file explorer": ["finder"],
        "windows explorer": ["finder"],
        "recycle bin":   ["trash"],
        "task view":     ["mission control"],
        "task bar":      ["dock"],
        "start menu":    ["spotlight", "launchpad"],
        "right click":   ["right-click", "secondary click", "two-finger"],
        "sign out":      ["log out"],
        "log off":       ["log out"],
        "snap assist":   ["split", "tile"],
        "command prompt":["terminal"],
        "power shell":   ["terminal"],
        "my computer":   ["finder"],
        "snipping tool": ["screenshot"],
        "nearby share":  ["airdrop"],
        "quick settings":["control center"],
        "force quit":    ["force quit"],
    ]

    /// Expand one token to its accepted term set.
    private static func expand(_ token: String) -> [String] {
        [token] + (synonyms[token] ?? [])
    }

    /// Filler words stripped from free-text queries ("how do I copy a file").
    private static let stopwords: Set<String> = [
        "a", "an", "the", "how", "do", "i", "to", "in", "of", "on", "for",
        "me", "my", "can", "is", "it", "this", "that", "what", "when", "you",
        "your", "get", "make", "show", "find", "and", "or", "not", "please",
        "does", "want", "with", "from", "using", "use", "way", "some", "into",
        "out", "all", "would", "like", "need", "where", "which", "who", "am",
    ]

    /// Filter + rank items for a query.
    ///
    /// Strategy: each query token becomes a group of acceptable terms
    /// (synonym-expanded; stopwords ignored; two-word phrases like
    /// "task manager" handled first). Items are ranked by how many groups
    /// they satisfy — results keep only the best-matching tier, so free-text
    /// questions still surface the right function even when not every word hits.
    static func filter(_ items: [Item], query: String) -> [Item] {
        let normalized = query
            .lowercased()
            .replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: " ")
        let rawTokens = normalized.split(separator: " ").map(String.init)
        guard !rawTokens.isEmpty else { return items }

        var groups: [[String]] = []
        var i = 0
        while i < rawTokens.count {
            if i + 1 < rawTokens.count,
               let phrase = phrases["\(rawTokens[i]) \(rawTokens[i + 1])"] {
                groups.append(phrase)
                i += 2
            } else {
                let t = rawTokens[i]
                if !stopwords.contains(t) { groups.append(expand(t)) }
                i += 1
            }
        }
        guard !groups.isEmpty else { return items }

        // Score every item: how many groups it satisfies + match quality.
        var scored: [(item: Item, matched: Int, weight: Int)] = []
        var bestCount = 0
        for item in items {
            let index = item.searchIndex
            let title = item.title.lowercased()
            let win = (item.winEquivalent ?? "").lowercased()
            var matched = 0
            var weight = 0
            for group in groups {
                var hit = false
                for term in group where index.contains(term) {
                    hit = true
                    if title.contains(term)   { weight += 4 }
                    else if win.contains(term) { weight += 3 }
                    else                       { weight += 1 }
                }
                if hit { matched += 1 }
            }
            if matched > 0 {
                scored.append((item, matched, weight))
                bestCount = max(bestCount, matched)
            }
        }

        // Keep only the best-satisfying tier; rank it by match weight.
        return scored
            .filter { $0.matched == bestCount }
            .sorted { $0.weight > $1.weight }
            .map(\.item)
    }
}
