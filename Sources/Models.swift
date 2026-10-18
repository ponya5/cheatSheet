import Foundation
import Combine
import SwiftUI
import AppKit

enum Category: String, CaseIterable, Hashable {
    case startHere   = "Start Here"
    case essentials  = "Essentials"
    case finder      = "Finder & Files"
    case appsWindows = "Apps & Windows"
    case screenshots = "Screenshots"
    case text        = "Text Editing"
    case system      = "System"
    case web         = "Web & Safari"
    case trackpad    = "Trackpad & Gestures"
    case proTips     = "Pro Tips"

    var icon: String {
        switch self {
        case .startHere:   return "map.fill"
        case .essentials:  return "command"
        case .finder:      return "folder.fill"
        case .appsWindows: return "macwindow"
        case .screenshots: return "camera.viewfinder"
        case .text:        return "text.cursor"
        case .system:      return "gearshape.fill"
        case .web:         return "safari"
        case .trackpad:    return "hand.tap.fill"
        case .proTips:     return "wand.and.stars"
        }
    }
}

struct Item: Identifiable, Hashable {
    let id: String
    let category: Category
    let title: String
    /// Key combo shown as keycaps. Prefix a token with "~" to render it as a
    /// plain separator (e.g. "then", "or") instead of a keycap.
    let keys: [String]
    /// The Windows way of doing the same thing — also indexed for search.
    let winEquivalent: String?
    let detail: String
    let keywords: [String]

    var isTip: Bool { keys.isEmpty }

    /// Everything the search looks through.
    var searchIndex: String {
        ([title, (winEquivalent ?? ""), detail] + keys + keywords)
            .joined(separator: " ")
            .lowercased()
    }
}

final class FavoritesStore: ObservableObject {
    // @Published is a macro whose plugin ships only with Xcode — drive the
    // publisher manually so the file compiles with Command Line Tools alone.
    let objectWillChange = ObservableObjectPublisher()

    private(set) var ids: Set<String> {
        willSet { objectWillChange.send() }
    }
    private let storageKey = "macswitch.favorites.v1"

    init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UserDefaults.standard.set(Array(ids), forKey: storageKey)
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }
}

/// All UI state in one plain ObservableObject — avoids the @State/@Published
/// macros, which are unavailable without full Xcode.
final class ViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    var selection: SidebarItem = .all { willSet { objectWillChange.send() } }
    var query = "" {
        willSet { objectWillChange.send() }
        didSet { quickIndex = 0 }
    }
    var searchPresented = false { willSet { objectWillChange.send() } }

    // Quick-panel state
    var quickIndex = 0 { willSet { objectWillChange.send() } }
    /// Category filter inside the quick panel — nil = All.
    var quickCategory: Category? = nil { willSet { objectWillChange.send() } }

    /// Clicked card in the main window — stays highlighted.
    var selectedCardId: String? = nil { willSet { objectWillChange.send() } }

    /// Item the pointer is currently hovering — its keycaps react to the
    /// physical keyboard (see KeyLightMonitor).
    var hoverItemId: String? = nil { willSet { objectWillChange.send() } }

    /// Whether the main window floats above other apps.
    var mainFloats = true { willSet { objectWillChange.send() } }

    // Desktop widget
    var widgetVisible = false { willSet { objectWillChange.send() } }
    var widgetQuery = "" {
        willSet { objectWillChange.send() }
        didSet { widgetResultOffset = 0 }
    }
    var widgetResultOffset = 0 { willSet { objectWillChange.send() } }

    /// Physical keys currently held, translated to dataset label vocabulary.
    /// `modKeys` = modifier flags; `charKeys` = keyCode → label.
    var modKeys: Set<String> = [] { willSet { objectWillChange.send() } }
    var charKeys: [UInt16: String] = [:] { willSet { objectWillChange.send() } }

    var pressedKeys: Set<String> {
        modKeys.union(charKeys.values)
    }

    var hoveredItem: Item? {
        ItemData.all.first { $0.id == hoverItemId }
    }

    /// Should this keycap render as "pressed"? Only lights when its own item
    /// is the one being hovered.
    func isPressed(_ label: String, on itemId: String?) -> Bool {
        guard let itemId, hoverItemId == itemId else { return false }
        return pressedKeys.contains { capMatches(cap: label, eventLabel: $0) }
    }

    /// Does a dataset keycap label match a pressed physical key?
    func capMatches(cap: String, eventLabel: String) -> Bool {
        if cap == eventLabel { return true }
        if cap == "1-9" { return eventLabel.count == 1 && "123456789".contains(eventLabel) }
        if cap == "+" { return eventLabel == "=" } // unshifted '=' is the '+' key
        return false
    }

    func binding<T>(_ keyPath: ReferenceWritableKeyPath<ViewModel, T>) -> Binding<T> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }
}
