import SwiftUI

// MARK: - Sidebar selection

enum SidebarItem: Hashable {
    case all
    case favorites
    case category(Category)

    var title: String {
        switch self {
        case .all: return "All Tips"
        case .favorites: return "Favorites"
        case .category(let c): return c.rawValue
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    // Manual property-wrapper storage — the @State/@EnvironmentObject
    // spellings are macros unavailable in the CLT toolchain.
    private var _vm = EnvironmentObject<ViewModel>()
    private var _favorites = EnvironmentObject<FavoritesStore>()
    private var _controller = EnvironmentObject<AppController>()
    private var _openWindow = Environment<OpenWindowAction>(\.openWindow)

    private var vm: ViewModel { _vm.wrappedValue }
    private var favorites: FavoritesStore { _favorites.wrappedValue }
    private var controller: AppController { _controller.wrappedValue }

    private var baseItems: [Item] {
        switch vm.selection {
        case .all:
            return ItemData.all
        case .favorites:
            return ItemData.all.filter { favorites.contains($0.id) }
        case .category(let c):
            return ItemData.all.filter { $0.category == c }
        }
    }

    private var results: [Item] {
        SearchEngine.filter(baseItems, query: vm.query)
    }

    /// Sections for the grid. "All" groups results by category for context.
    private var sections: [(Category?, [Item])] {
        switch vm.selection {
        case .all:
            return Category.allCases
                .map { c in (c, results.filter { $0.category == c }) }
                .filter { !$0.1.isEmpty }
        default:
            return [(nil, results)]
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            detail
                .background(WindowAccessor { w in
                    controller.mainWindow = w
                    if vm.mainFloats { w.level = .floating }
                })
                .navigationTitle(vm.selection.title)
                .searchable(text: vm.binding(\.query),
                            isPresented: vm.binding(\.searchPresented),
                            placement: .toolbar,
                            prompt: Text("Search — try 'ctrl c', 'print screen', 'task manager'"))
                .toolbar {
                    ToolbarItem(placement: .status) {
                        Text("\(results.count) \(results.count == 1 ? "tip" : "tips")")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    ToolbarItem {
                        Button {
                            vm.mainFloats.toggle()
                            controller.mainWindow?.level = vm.mainFloats ? .floating : .normal
                        } label: {
                            Image(systemName: vm.mainFloats ? "pin.fill" : "pin")
                        }
                        .help(vm.mainFloats ? "Window floats on top — click to unpin" : "Pin window above other apps")
                    }
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            vm.searchPresented = true
        }
        .onAppear {
            controller.openMainWindow = { [self] in
                _openWindow.wrappedValue(id: "main")
            }
        }
    }

    private var sidebar: some View {
        List(selection: Binding<SidebarItem?>(
            get: { vm.selection },
            set: { if let v = $0 { vm.selection = v } }
        )) {
            Section {
                Label("All Tips", systemImage: "square.grid.2x2.fill")
                    .tag(SidebarItem.all)
                Label("Favorites", systemImage: "star.fill")
                    .badge(ItemData.all.filter { favorites.contains($0.id) }.count)
                    .tag(SidebarItem.favorites)
            }
            Section("Categories") {
                ForEach(Category.allCases, id: \.self) { c in
                    Label(c.rawValue, systemImage: c.icon)
                        .badge(ItemData.all.filter { $0.category == c }.count)
                        .tag(SidebarItem.category(c))
                }
            }

            Section {
                Label("Press ⌃⌥Space anywhere\nfor quick search", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }

    private var detail: some View {
        ScrollView {
            if results.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 14)],
                    alignment: .leading, spacing: 14,
                    pinnedViews: [.sectionHeaders]
                ) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        Section {
                            ForEach(section.1) { item in
                                ShortcutCard(item: item)
                            }
                        } header: {
                            if let cat = section.0 {
                                Text(cat.rawValue)
                                    .font(.title3.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: vm.selection == .favorites ? "star" : "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            if vm.selection == .favorites && vm.query.isEmpty {
                Text("No favorites yet")
                    .font(.title3.bold())
                Text("Hover a card and click the star to pin it here.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No matches for \"\(vm.query)\"")
                    .font(.title3.bold())
                Text("Try the Windows term — 'task manager', 'alt tab', 'print screen', 'explorer'…")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
        .padding(.horizontal, 40)
    }
}

// MARK: - Shortcut card

struct ShortcutCard: View {
    private var _vm = EnvironmentObject<ViewModel>()
    private var _favorites = EnvironmentObject<FavoritesStore>()
    private var _hovering = State(initialValue: false)
    let item: Item

    private var vm: ViewModel { _vm.wrappedValue }
    private var favorites: FavoritesStore { _favorites.wrappedValue }
    private var hovering: Bool {
        get { _hovering.wrappedValue }
        nonmutating set { _hovering.wrappedValue = newValue }
    }
    private var isFavorite: Bool { favorites.contains(item.id) }
    private var selected: Bool { vm.selectedCardId == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                if item.isTip {
                    Image(systemName: "lightbulb.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                        .frame(width: 30, height: 30)
                } else {
                    KeyComboView(keys: item.keys, itemId: item.id)
                }
                Spacer()
                Button { favorites.toggle(item.id) } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering || isFavorite ? 1 : 0)
            }
            .frame(minHeight: 30)

            Text(item.title)
                .font(.headline)

            if let win = item.winEquivalent, win != "—" {
                HStack(spacing: 5) {
                    Image(systemName: "pc")
                        .font(.caption2)
                    Text(win)
                        .font(.caption)
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(.blue.opacity(0.1)))
            }

            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(selected ? 0.12 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.accentColor
                                 : .primary.opacity(hovering ? 0.16 : 0.07),
                        lineWidth: selected ? 2 : 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.12 : 0.05),
                radius: hovering ? 8 : 3, y: 2)
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.snappy(duration: 0.15), value: hovering)
        .animation(.snappy(duration: 0.15), value: selected)
        .onHover { h in
            hovering = h
            vm.hoverItemId = h ? item.id : (vm.hoverItemId == item.id ? nil : vm.hoverItemId)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            vm.selectedCardId = selected ? nil : item.id
        }
    }
}

// MARK: - Window accessor

/// Resolves the NSWindow hosting this view (SwiftUI gives no direct handle).
struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let w = view.window { onResolve(w) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let w = nsView.window { onResolve(w) }
    }
}

// MARK: - Keycaps

struct KeyComboView: View {
    let keys: [String]
    var itemId: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { token in
                if token.hasPrefix("~") {
                    Text(String(token.dropFirst()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    KeyCap(label: token, itemId: itemId)
                }
            }
        }
    }
}

struct KeyCap: View {
    let label: String
    var itemId: String? = nil
    private var _vm = EnvironmentObject<ViewModel>()
    /// Briefly true after a click — flashes the cap so you know which key you hit.
    private var _pressed = State(initialValue: false)

    private var pressed: Bool {
        get { _pressed.wrappedValue }
        nonmutating set { _pressed.wrappedValue = newValue }
    }
    /// Physical key currently held on the keyboard — only when this cap's own
    /// card is hovered.
    private var keyDown: Bool { _vm.wrappedValue.isPressed(label, on: itemId) }

    private var active: Bool { pressed || keyDown }

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 8)
            .frame(minWidth: 30, minHeight: 30)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(active ? Color.accentColor : Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(active ? 0.02 : 0.18), radius: 0.5, y: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(active ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: active ? 1.5 : 0.5)
            )
            .scaleEffect(active ? 0.92 : 1)
            .animation(.snappy(duration: 0.12), value: active)
            .onTapGesture {
                pressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    pressed = false
                }
            }
    }
}
