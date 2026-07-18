# LoopBar

A native macOS menu-bar monitor for your recent local Cursor composers (agents, chats, and plans). It is deliberately **read-only** and never sends prompts or modifies Cursor work.

![Architecture](docs/architecture.svg)

## Run locally

Requirements: macOS 14+ and Xcode 15+.

```sh
swift run LoopBar
```

Click the island at the top of your screen (centered near the notch) to expand it. Click a row to open that chat in Cursor. Use the gear icon for settings.

To open in Xcode, create an App project and add the contents of `Sources/`, or open this Swift Package and select the `LoopBar` executable scheme.

## Monitor local Cursor composers

The app reads Cursor's live `composerHeaders` table in `state.vscdb` (not the lagging `conversation-search.db` index). It displays the three most recently updated non-archived, non-subagent composers and does not need an API key or network connection.

Cursor does not store a durable local agent run state, so composers updated within the last two minutes are shown as running; older composers are shown as unknown rather than inferred to be completed.

## Architecture

MVVM layout under `Sources/`:

- `App/` — `@main` entry and `AppDelegate`
- `Controllers/IslandPanelController` — NSPanel host, resize, screen observation only
- `ViewModels/IslandViewModel` — island chrome state (`IslandState`), content (`IslandContent`), hover/animation flags
- `Models/` — `CursorAgent`, `IslandState`, `IslandContent`
- `Services/AgentStore` — agent polling and error state only
- `Services/CursorAPI` — read-only live `composerHeaders` access
- `Geometry/IslandGeometry` — notch/screen frame math
- `Utilities/IslandMetrics` — sizing constants
- `Views/` — `IslandRootView`, `CompactIslandView`, `ExpandedIslandView`, `AgentRowView`, `MenuPanelView`, `SettingsView`

## Privacy

The app reads only Cursor's local `state.vscdb` composer headers. It makes no network requests and does not modify Cursor data.

## Build a distributable app

For signing, sandboxing, and an application icon, move `Sources/` into an Xcode macOS App target. The code already has no third-party dependencies.
