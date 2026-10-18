import AppKit

/// Lights up keycaps while their physical key is held — but only on the
/// shortcut card/row the pointer is hovering over, so you can "practice"
/// a combo and see which key you're pressing.
///
/// Matching rules: an event only highlights a cap when the hovered item's
/// combo contains that cap. Modifier keys (⌘⌥⇧⌃Fn) arrive via
/// `.flagsChanged`; character/special keys via `.keyDown`/`.keyUp`.
final class KeyLightMonitor {
    weak var vm: ViewModel?
    private var monitor: Any?

    func start(vm: ViewModel) {
        self.vm = vm
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        guard let vm else { return e }

        switch e.type {
        case .flagsChanged:
            vm.modKeys = modifierLabels(e.modifierFlags)
            return e

        case .keyDown:
            guard !e.isARepeat, let label = label(for: e) else { return e }
            vm.charKeys[e.keyCode] = label

            // Typing into a text field wins — the cap still lights up.
            if e.window?.firstResponder is NSTextView { return e }
            guard vm.hoverItemId != nil else { return e }

            // The pressed key is part of the hovered combo — swallow it so
            // pressing e.g. ⌘Q while practicing "Quit" doesn't quit the app.
            if matchesHoveredCombo(label, vm: vm) { return nil }

            // Any other plain key while hovering: swallow so arrows/space/tab
            // don't navigate the UI. ⌘/⌃ combos keep working normally.
            if e.modifierFlags.intersection([.command, .control]).isEmpty {
                return nil
            }
            return e

        case .keyUp:
            vm.charKeys.removeValue(forKey: e.keyCode)
            return e

        default:
            return e
        }
    }

    /// Event produced `label` — does it match a cap on the hovered item?
    private func matchesHoveredCombo(_ label: String, vm: ViewModel) -> Bool {
        guard let hovered = vm.hoveredItem else { return false }
        return hovered.keys.contains {
            !$0.hasPrefix("~") && vm.capMatches(cap: $0, eventLabel: label)
        }
    }

    private func modifierLabels(_ f: NSEvent.ModifierFlags) -> Set<String> {
        var s: Set<String> = []
        if f.contains(.command)  { s.insert("⌘") }
        if f.contains(.option)   { s.insert("⌥") }
        if f.contains(.control)  { s.insert("⌃") }
        if f.contains(.shift)    { s.insert("⇧") }
        if f.contains(.function) { s.insert("Fn") }
        return s
    }

    /// Map a key event to the vocabulary used in the dataset labels.
    private func label(for e: NSEvent) -> String? {
        switch e.keyCode {
        case 36, 76:  return "Return"
        case 48:      return "Tab"
        case 49:      return "Space"
        case 51, 117: return "Delete"
        case 53:      return "Esc"
        case 123:     return "←"
        case 124:     return "→"
        case 125:     return "↓"
        case 126:     return "↑"
        case 99:      return "F3"
        case 103:     return "F11"
        default:      break
        }
        guard let chars = e.charactersIgnoringModifiers, let c = chars.first else {
            return nil
        }
        return String(c).uppercased()
    }
}
