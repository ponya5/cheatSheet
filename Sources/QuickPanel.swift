import SwiftUI
import AppKit
import Combine

/// Borderless floating panel that can take keyboard focus.
final class QuickPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return } // Esc anywhere in panel
        super.keyDown(with: event)
    }
}

/// Owns the floating quick-search window.
final class QuickPanelController {
    private let panel: QuickPanel
    private let host: NSViewController
    private let vm: ViewModel
    /// Whether the main window was open when the panel was invoked —
    /// if so we leave the app active when the panel closes.
    private var mainWindowWasVisible = false
    private var hasShown = false

    init(vm: ViewModel, favorites: FavoritesStore) {
        self.vm = vm

        let root = QuickSearchView()
            .environmentObject(vm)
            .environmentObject(favorites)
        let host = NSHostingController(rootView: root)
        self.host = host

        let p = QuickPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.minSize = NSSize(width: 480, height: 300)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host.view
        p.isReleasedWhenClosed = false
        panel = p

        p.onEscape = { [weak self] in self?.hide() }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: p, queue: .main
        ) { [weak self] _ in self?.hide() }
        NotificationCenter.default.addObserver(
            forName: .closeQuickPanel, object: nil, queue: .main
        ) { [weak self] _ in self?.hide() }
        NotificationCenter.default.addObserver(
            forName: .openQuickPanel, object: nil, queue: .main
        ) { [weak self] note in
            self?.show(prefillQuery: note.userInfo?["query"] as? String)
        }
        // Magnetic edge docking while dragging.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: p, queue: .main
        ) { [weak self] _ in self?.snapToEdges() }
    }

    /// Snap the panel to screen edges when dragged within ~28pt of them.
    private func snapToEdges() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let f = screen.visibleFrame
        let frame = panel.frame
        var o = frame.origin
        let margin: CGFloat = 10, snap: CGFloat = 28
        if abs(frame.minX - f.minX) < snap { o.x = f.minX + margin }
        if abs(frame.maxX - f.maxX) < snap { o.x = f.maxX - frame.width - margin }
        if abs(frame.minY - f.minY) < snap { o.y = f.minY + margin }
        if abs(frame.maxY - f.maxY) < snap { o.y = f.maxY - frame.height - margin }
        if o != frame.origin { panel.setFrameOrigin(o) }
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show(prefillQuery: String? = nil) {
        // Other visible windows of our app (the main window).
        let others = NSApp.windows.filter { $0 !== panel && $0.isVisible }
        let mainWasKey = others.contains { $0 === NSApp.keyWindow }
        mainWindowWasVisible = !others.isEmpty
        vm.query = prefillQuery ?? ""
        vm.quickIndex = 0

        // Center ~25% from the top on first open only — after that the panel
        // reappears wherever the user left it.
        if !hasShown, let screen = NSScreen.main {
            let f = screen.visibleFrame
            let x = f.midX - panel.frame.width / 2
            let y = f.maxY - f.height * 0.25 - panel.frame.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        hasShown = true

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // If the main window wasn't in use, push it back so opening the
        // panel doesn't bring the full app window over the user's apps.
        if !mainWasKey { others.forEach { $0.orderBack(nil) } }
        DispatchQueue.main.async { self.focusSearchField() }
    }

    func hide() {
        guard panel.isVisible else { return }
        vm.hoverItemId = nil
        vm.charKeys.removeAll()
        vm.modKeys = []
        panel.orderOut(nil)
        // Give focus back to whatever was in front before us.
        if !mainWindowWasVisible { NSApp.hide(nil) }
    }

    private func focusSearchField() {
        if let field = editableField(in: panel.contentView) {
            panel.makeFirstResponder(field)
        }
    }

    private func editableField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let f = view as? NSTextField, f.isEditable { return f }
        for sub in view.subviews {
            if let hit = editableField(in: sub) { return hit }
        }
        return nil
    }
}

// MARK: - Native search field (focus + key handling)

/// NSTextField wrapper so the panel controls focus and intercepts
/// ↑/↓/↩/esc while the field has the cursor.
struct SearchField: NSViewRepresentable {
    var text: Binding<String>
    var fontSize: CGFloat = 22
    var placeholder = "Type the Windows shortcut — 'ctrl c', 'alt tab', 'print screen'…"
    var onUp: () -> Void
    var onDown: () -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .light)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: NSFont.systemFont(ofSize: max(10, fontSize - 2), weight: .light),
                .foregroundColor: NSColor.placeholderTextColor,
            ]
        )
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text.wrappedValue {
            nsView.stringValue = text.wrappedValue
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: SearchField
        init(parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onUp(); return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onDown(); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel(); return true
            default:
                return false
            }
        }
    }
}

// MARK: - Panel content

struct QuickSearchView: View {
    private var _vm = EnvironmentObject<ViewModel>()
    private var _favorites = EnvironmentObject<FavoritesStore>()

    private var vm: ViewModel { _vm.wrappedValue }
    private var favorites: FavoritesStore { _favorites.wrappedValue }

    /// Category-scope for the panel; nil = everything.
    private var baseItems: [Item] {
        guard let c = vm.quickCategory else { return ItemData.all }
        return ItemData.all.filter { $0.category == c }
    }

    private var results: [Item] {
        vm.query.isEmpty ? suggested : SearchEngine.filter(baseItems, query: vm.query)
    }

    /// Empty-query view: the selected category, or favorites + essentials.
    private var suggested: [Item] {
        if vm.quickCategory != nil { return baseItems }
        let favs = ItemData.all.filter { favorites.contains($0.id) }
        let essentials = ItemData.all.filter { $0.category == .essentials }
        return Array((favs + essentials).prefix(9))
    }

    private var selectedIndex: Int {
        min(vm.quickIndex, max(0, results.count - 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search row
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.secondary)
                SearchField(
                    text: vm.binding(\.query),
                    onUp: { move(-1) },
                    onDown: { move(1) },
                    onSubmit: { reveal(results[safe: selectedIndex]) },
                    onCancel: { NotificationCenter.default.post(name: .closeQuickPanel, object: nil) }
                )
                Button {
                    NotificationCenter.default.post(name: .closeQuickPanel, object: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                }
                .buttonStyle(PressEffectButtonStyle())
                .help("Close (esc)")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // View picker — filter the results by category
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All", icon: "square.grid.2x2.fill",
                         selected: vm.quickCategory == nil) {
                        vm.quickCategory = nil
                    }
                    ForEach(Category.allCases, id: \.self) { c in
                        chip(c.rawValue, icon: c.icon,
                             selected: vm.quickCategory == c) {
                            vm.quickCategory = c
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 8)

            Divider()

            // Results
            if results.isEmpty {
                VStack(spacing: 8) {
                    Text("No matches for \"\(vm.query)\"")
                        .font(.headline)
                    Text("Try a Windows term: 'explorer', 'task manager', 'prtsc', 'alt f4'…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, item in
                                QuickRow(item: item, selected: idx == selectedIndex)
                                    .id(item.id)
                                    .onTapGesture(count: 2) { reveal(item) }
                                    .onTapGesture(count: 1) { vm.quickIndex = idx }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: vm.quickIndex) { _, newValue in
                        if let item = results[safe: newValue] {
                            proxy.scrollTo(item.id, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack(spacing: 14) {
                hint("↑↓", "navigate")
                hint("↩", "open in app")
                hint("esc", "close")
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .toggleWidget, object: nil)
                } label: {
                    Label("Widget", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(PressEffectButtonStyle())
                .help("Show a tip widget on the desktop")
                Text("⌃⌥Space anywhere").foregroundStyle(.tertiary)
            }
            .font(.caption)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func chip(_ title: String, icon: String, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(selected ? Color.accentColor
                                            : Color.primary.opacity(0.08))
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key).bold()
            Text(action).foregroundStyle(.secondary)
        }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        vm.quickIndex = min(max(vm.quickIndex + delta, 0), results.count - 1)
    }

    /// Reveal the item as a highlighted card in the main app window.
    private func reveal(_ item: Item?) {
        guard let item else { return }
        vm.query = ""
        vm.selection = .all
        vm.selectedCardId = item.id
        NotificationCenter.default.post(name: .openMainApp, object: nil)
    }
}

/// One result row: Windows way on the left, Mac keycaps on the right.
struct QuickRow: View {
    private var _vm = EnvironmentObject<ViewModel>()
    let item: Item
    let selected: Bool

    private var vm: ViewModel { _vm.wrappedValue }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let win = item.winEquivalent, win != "—" {
                    HStack(spacing: 4) {
                        Image(systemName: "pc")
                            .font(.system(size: 8))
                        Text(win)
                            .font(.caption)
                    }
                    .foregroundStyle(selected ? .white.opacity(0.85) : .blue)
                } else {
                    Text(item.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(selected ? .white.opacity(0.7) : .secondary)
                }
            }
            Spacer(minLength: 8)
            if item.isTip {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(selected ? .white : .yellow)
            } else {
                KeyComboView(keys: item.keys, itemId: item.id)
                    .opacity(selected ? 1 : 0.95)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor : .clear)
                .padding(.horizontal, 8)
        )
        .foregroundStyle(selected ? Color.white : Color.primary)
        .contentShape(Rectangle())
        .onHover { h in
            vm.hoverItemId = h ? item.id : (vm.hoverItemId == item.id ? nil : vm.hoverItemId)
        }
    }
}

extension Notification.Name {
    static let closeQuickPanel = Notification.Name("macswitch.closeQuickPanel")
    static let openQuickPanel = Notification.Name("macswitch.openQuickPanel")
    static let toggleWidget = Notification.Name("macswitch.toggleWidget")
    static let openMainApp = Notification.Name("macswitch.openMainApp")
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Desktop widget

/// A small widget that lives on the desktop — under normal windows, above the
/// wallpaper, on every space. Can take keyboard focus for its search field
/// without activating the app (nonactivating panel).
final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class WidgetPanelController {
    private let panel: DesktopPanel
    private let host: NSViewController
    private let vm: ViewModel

    init(vm: ViewModel) {
        self.vm = vm
        let root = WidgetView().environmentObject(vm)
        let host = NSHostingController(rootView: root)
        self.host = host

        let p = DesktopPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false
        )
        p.minSize = NSSize(width: 340, height: 180)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        // Desktop level — sits above the wallpaper, below normal windows.
        p.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        )
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = host.view
        p.isReleasedWhenClosed = false
        panel = p
    }

    func show() {
        if !panel.isVisible {
            // Bottom-right of the main screen on first show.
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(
                    x: f.maxX - panel.frame.width - 24,
                    y: f.minY + 24
                ))
            }
            panel.orderFrontRegardless()
        }
    }

    func hide() { panel.orderOut(nil) }
}

/// Pressed-state feedback for the small widget/footer buttons.
struct PressEffectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.accentColor : Color.secondary)
            .scaleEffect(configuration.isPressed ? 0.7 : 1.0)
            .animation(.snappy(duration: 0.1), value: configuration.isPressed)
    }
}

struct WidgetView: View {
    private var _vm = EnvironmentObject<ViewModel>()
    private var vm: ViewModel { _vm.wrappedValue }

    private var searchResults: [Item] {
        SearchEngine.filter(ItemData.all, query: vm.widgetQuery)
    }

    private var searching: Bool { !vm.widgetQuery.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar + controls
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                SearchField(
                    text: vm.binding(\.widgetQuery),
                    fontSize: 13,
                    placeholder: "Ask — 'how do I screenshot', 'ctrl c'…",
                    onUp: { move(-1) },
                    onDown: { move(1) },
                    onSubmit: {},
                    onCancel: { vm.widgetQuery = "" }
                )
                iconButton("macwindow", "Open MacSwitch") {
                    NotificationCenter.default.post(name: .openMainApp, object: nil)
                }
                iconButton("xmark", "Hide widget") {
                    NotificationCenter.default.post(name: .toggleWidget, object: nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 7)

            if searching {
                Divider()
                Group {
                    if searchResults.isEmpty {
                        Text("No match for \"\(vm.widgetQuery)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        // Up to ~3 rows visible, scroll for the rest.
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(searchResults.enumerated()),
                                        id: \.element.id) { idx, result in
                                    QuickRow(item: result,
                                             selected: idx == selectedResult)
                                        .onTapGesture(count: 2) { openPanel() }
                                        .onTapGesture { vm.widgetResultOffset = idx }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .frame(maxHeight: 3 * 46)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.primary.opacity(0.1), lineWidth: 0.5)
        )
        .animation(.snappy(duration: 0.22), value: searching)
    }

    private func iconButton(_ icon: String, _ help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(PressEffectButtonStyle())
        .help(help)
    }

    private var selectedResult: Int {
        min(vm.widgetResultOffset, max(0, searchResults.count - 1))
    }

    /// Up/down cycles the selected search result (wraps).
    private func move(_ delta: Int) {
        let count = searchResults.count
        guard count > 0 else { return }
        vm.widgetResultOffset = (vm.widgetResultOffset + delta + count) % count
    }

    /// Open the quick panel pre-filled with the widget's query.
    private func openPanel() {
        NotificationCenter.default.post(
            name: .openQuickPanel, object: nil,
            userInfo: ["query": vm.widgetQuery]
        )
    }
}
