import SwiftUI
import Combine

extension Notification.Name {
    static let focusSearch = Notification.Name("macswitch.focusSearch")
}

/// Owns the global hotkey and the quick-search panel.
final class AppController: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private let hotkeys = HotKeyManager()
    private let keyLight = KeyLightMonitor()
    private(set) var panel: QuickPanelController?
    private var widget: WidgetPanelController?
    weak var mainWindow: NSWindow?
    var openMainWindow: (() -> Void)?
    private weak var vm: ViewModel?

    func attach(vm: ViewModel, favorites: FavoritesStore) {
        guard panel == nil else { return }
        self.vm = vm
        let controller = QuickPanelController(vm: vm, favorites: favorites)
        panel = controller
        hotkeys.onPress = { [weak self] in self?.panel?.toggle() }
        hotkeys.register()
        keyLight.start(vm: vm)

        widget = WidgetPanelController(vm: vm)
        NotificationCenter.default.addObserver(
            forName: .toggleWidget, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let vm = self.vm else { return }
            self.setWidgetVisible(!vm.widgetVisible)
        }
        // Restore widget if it was open last launch.
        if UserDefaults.standard.bool(forKey: "widget.visible") {
            setWidgetVisible(true)
        }

        NotificationCenter.default.addObserver(
            forName: .openMainApp, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.openMainWindow?()
            NSApp.activate()
            self.mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func setWidgetVisible(_ visible: Bool) {
        vm?.widgetVisible = visible
        UserDefaults.standard.set(visible, forKey: "widget.visible")
        visible ? widget?.show() : widget?.hide()
    }
}

@main
struct MacSwitchApp: App {
    // Property wrappers spelled out — the macro plugin isn't in the CLT toolchain.
    private var _vm = StateObject(wrappedValue: ViewModel())
    private var _favorites = StateObject(wrappedValue: FavoritesStore())
    private var _controller = StateObject(wrappedValue: AppController())

    private var vm: ViewModel { _vm.wrappedValue }
    private var favorites: FavoritesStore { _favorites.wrappedValue }
    private var controller: AppController { _controller.wrappedValue }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(vm)
                .environmentObject(favorites)
                .environmentObject(controller)
                .frame(minWidth: 820, minHeight: 520)
                .onAppear { controller.attach(vm: vm, favorites: favorites) }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Search Shortcuts…") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Quick Search…") {
                    controller.panel?.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        MenuBarExtra("MacSwitch", systemImage: "command") {
            Button("Quick Search") { controller.panel?.toggle() }
            Button("Open MacSwitch") {
                controller.openMainWindow?()
                NSApp.activate()
                controller.mainWindow?.makeKeyAndOrderFront(nil)
            }
            Text("Global hotkey: ⌃⌥Space")
            Toggle("Desktop Widget", isOn: Binding(
                get: { vm.widgetVisible },
                set: { controller.setWidgetVisible($0) }
            ))
            Divider()
            Button("Quit MacSwitch") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}
