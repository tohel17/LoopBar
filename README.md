# LoopBar

A native macOS menu-bar monitor for your recent local Cursor conversations. It is deliberately **read-only** and never sends prompts or modifies Cursor work.

![Architecture](docs/architecture.svg)

## Run locally

Requirements: macOS 14+ and Xcode 15+.

```sh
swift run LoopBar
```

Click the menu-bar icon to open the panel; use Settings to change the refresh interval.

To open in Xcode, create an App project and add the contents of `Sources/`, or open this Swift Package and select the `LoopBar` executable scheme.

## Monitor local Cursor conversations

The app reads Cursor's local, unarchived conversation index directly. It displays the three most recently updated conversations and does not need an API key or network connection.

Cursor does not store a durable local agent run state, so conversations updated within the last two minutes are shown as running; older conversations are shown as unknown rather than inferred to be completed.

## Architecture

- `AgentStore`: observable state, polling lifecycle, completion detection, error state.
- `LocalCursorAgentAPI`: reads Cursor's local conversation index in read-only mode.
- `MenuPanelView`: a compact, dark SwiftUI panel that expands from the menu bar like a notch.
- SwiftUI views: compact summary, expandable agent list, settings.

## Privacy

The app reads only Cursor's local conversation index. It makes no network requests and does not modify Cursor data.

## Build a distributable app

For signing, sandboxing, and an application icon, move `Sources/` into an Xcode macOS App target. The code already has no third-party dependencies.
