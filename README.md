# MacSwitch

A small native macOS cheat-sheet app for Windows users switching to Mac.
Every shortcut shows its Windows equivalent, and the search understands
Windows terms — type `ctrl c`, `alt tab`, `task manager`, `print screen`
and it finds the Mac way.

## Features

- **~100 shortcuts, tips & concept mappings** across 10 categories
  (Start Here, Essentials, Finder, Windows, Screenshots, Text, System,
  Web, Trackpad, Pro Tips)
- **Smart search** — searches titles, details, keywords *and* the Windows
  equivalents, with a synonym table (ctrl→⌘, alt→⌥, prtsc→screenshot…)
- **Global quick search** — press **⌃⌥Space** anywhere to open a
  Spotlight-style panel. `↑↓` navigate, `↩` copies the Mac shortcut,
  `esc` closes. Also reachable from the menu-bar ⌘ icon.
- **Favorites** — hover a card, click the star
- Cards show: Mac keycaps · Windows equivalent · description

## Build & run

No Xcode needed — just Command Line Tools:

```bash
./build.sh          # compiles and bundles MacSwitch.app
open MacSwitch.app
```

The hotkey is registered in `Sources/HotKey.swift` (`kVK_Space` +
`controlKey|optionKey`); change the keyCode/modifiers there if ⌃⌥Space
conflicts with another tool.
