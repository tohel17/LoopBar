# LoopBar MVVM Architecture Refactor

**Date:** 2026-07-18  
**Status:** Approved for planning  
**Product name:** LoopBar (unchanged)

## Goal

Refactor LoopBar into a clean MVVM architecture with clear layer boundaries. Preserve existing visual behavior for the compact pill and agent list, while introducing typed island state/content and an in-panel settings/logs content switch.

## Non-goals

- Renaming the package, executable, or user-facing “LoopBar” branding
- Real hover expand/collapse behavior
- Implementing a functional logs feature
- Visual redesign of the island
- Automated UI test suite in this pass

## Decisions (locked)

| Topic | Choice |
|---|---|
| Naming | Keep LoopBar package/product; reorganize under `Sources/` |
| `IslandState.loading` / `.notification` | Wire to existing connecting/error moments; compact↔expanded look unchanged |
| `IslandContent` | Drive expanded body: agents / in-panel settings / logs placeholder |
| Hover | `@Published isHovered` stub only — no behavior change |
| Approach | Strict MVVM: thin AppKit controller, ViewModel owns UI state, pure geometry helper |

## Target layout

```
Sources/
├── App/
│   ├── LoopBarApp.swift
│   └── AppDelegate.swift
├── Controllers/
│   └── IslandPanelController.swift
├── ViewModels/
│   └── IslandViewModel.swift
├── Models/
│   ├── Agent.swift
│   ├── IslandState.swift
│   └── IslandContent.swift
├── Services/
│   ├── CursorAPI.swift
│   ├── AgentStore.swift
│   └── Settings.swift
├── Geometry/
│   └── IslandGeometry.swift
├── Views/
│   ├── IslandRootView.swift
│   ├── CompactIslandView.swift
│   ├── ExpandedIslandView.swift
│   ├── AgentRowView.swift
│   ├── MenuPanelView.swift
│   └── SettingsView.swift
└── Utilities/
    └── IslandMetrics.swift
```

`Package.swift` continues to target `Sources/` as a single executable target (no product rename).

## Layer responsibilities

### IslandPanelController (AppKit only)

**Owns:**
- Creating the `NSPanel` (nonactivating, borderless, floating, clear background)
- Hosting `IslandRootView` via `NSHostingView`
- Resizing/repositioning via `setFrame` (animated and non-animated)
- Observing `NSApplication.didChangeScreenParametersNotification`
- Observing ViewModel/store publishers that require a panel size refresh

**Does not own:**
- Compact/expanded/loading/notification semantics
- Notch/screen frame math
- Agent polling or Cursor I/O

### IslandViewModel

`@MainActor final class IslandViewModel: ObservableObject`

**Published state:**
- `state: IslandState`
- `content: IslandContent`
- `isHovered: Bool` (stub; unused by views in this pass)
- `isAnimating: Bool` (true during panel resize animation window)
- `notificationMessage: String?` (mirrors store errors for `.notification`)

**Actions:**
- `toggleExpanded()` — spring-matched compact ↔ expanded (same response/damping as today)
- `selectContent(_:)` — switch agents / settings / logs
- `setHovered(_:)` — reserved
- Sync from `AgentStore`: when expanded-like and refreshing/empty → `.loading`; when error present → `.notification` (expanded chrome); clear back to `.expanded` when appropriate

### Models

```swift
enum IslandState {
    case compact
    case expanded
    case loading
    case notification
}

enum IslandContent {
    case agents
    case settings
    case logs
}
```

`IslandState` helpers:
- `var isExpandedChrome: Bool` — true for `.expanded`, `.loading`, `.notification` (drives sizing/metrics)
- Existing `CursorAgent` / `AgentStatus` remain in `Models/Agent.swift`

### IslandGeometry

Pure functions / enum namespace:
- `targetScreen() -> NSScreen?` — prefer screen with `safeAreaInsets.top > 0`, else main/first
- `panelFrame(for contentSize: CGSize, on screen: NSScreen) -> NSRect` — current centering, visible-frame clamp, notch vs non-notch top inset — **moved verbatim** from today’s controller

### IslandMetrics

Moved to `Utilities/`. Sizing APIs keep equivalent inputs (`isExpanded`-style bool, agent count, hasError) so panel height/width stay identical.

### AgentStore

Unchanged role: agents list, lastUpdated, errorMessage, settings, polling, refresh. Calls `CursorAPI` instead of `LocalCursorAgentAPI`.

### CursorAPI

Rename of `LocalCursorAgentAPI` / `AgentAPI.swift`. Same read-only sqlite `composerHeaders` behavior and URL scheme.

## Data flow

```
AppDelegate
  ├─ AgentStore
  └─ IslandViewModel(store:)
       └─ IslandPanelController(viewModel:store:)
            hosts IslandRootView(viewModel, store)
            on state / agents / error changes:
              size = IslandMetrics.size(...)
              frame = IslandGeometry.panelFrame(for:on:)
              panel.setFrame(...)
```

Views bind to `IslandViewModel` for island chrome/content and to `AgentStore` for agent rows / refresh / settings values.

## View composition

| View | Role |
|---|---|
| `IslandRootView` | Host sizing + padding from metrics; embeds `MenuPanelView` |
| `CompactIslandView` | Header pill (status orb, titles, chevron); tap calls ViewModel toggle |
| `ExpandedIslandView` | Switches on `content`: agent list, in-panel settings, logs placeholder |
| `AgentRowView` | Extracted agent row (open in Cursor on tap) |
| `MenuPanelView` | Composes header + expanded body + footer + background + shape stroke/shadow |
| `SettingsView` | Existing form; presented in-panel when `content == .settings` (sheet removed) |

Private helpers (`StatusOrb`, `IslandShape`, `IslandIconButton`) remain file-private beside their consumers.

### Content UX (intentional change)

- Gear sets `content = .settings` (replaces modal sheet).
- Done/back from settings sets `content = .agents`.
- `ExpandedIslandView` implements a `.logs` placeholder pane (“Logs coming soon”).
- This pass adds **no** new footer/chrome control for logs. The case is handled in the switch for future callers of `selectContent(.logs)` only.

## State mapping detail

| Moment | `IslandState` | Expanded chrome? |
|---|---|---|
| Default / collapsed | `.compact` | No |
| User expanded, agents loaded, no error | `.expanded` | Yes |
| Expanded, waiting/connecting or refresh with empty list | `.loading` | Yes |
| Expanded with `errorMessage` | `.notification` | Yes |

Panel animation duration remains `0.24` with easeOut for AppKit frame; SwiftUI spring on toggle remains `response: 0.24, dampingFraction: 0.86`.

## Error handling

- Store errors continue to set `errorMessage`.
- ViewModel mirrors into `notificationMessage` and `.notification` when expanded-like.
- Red caption in expanded agents pane preserved.
- Cursor DB missing / sqlite failures unchanged through `CursorAPI`.

## Testing / verification

Manual checklist:
1. Launch: compact island under notch/menu bar
2. Click header: expands with same spring; agent list scrolls
3. Click header again: collapses
4. Refresh icon still refreshes
5. Gear opens in-panel settings; Done returns to agents
6. Agent row opens Cursor
7. Screen parameter change repositions panel
8. Error path still shows red caption when store fails

## Migration notes

- Move files; update imports only if needed (same module).
- Delete old nested `IslandRootView` from controller file.
- Update README architecture bullets to match new layout.
- Do not change `Package.swift` product name.

## Success criteria

1. Controller contains no screen/frame geometry formulas.
2. ViewModel owns island UI state via `@Published` properties.
3. AgentStore has no island expand/content logic.
4. Compact pill + agent list visuals match pre-refactor.
5. Settings appear in-panel via `IslandContent.settings`.
6. Source tree matches the target layout above.
