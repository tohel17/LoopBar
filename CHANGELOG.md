# LoopBar changelog

## Unreleased

### Added

- Added Homebrew cask installation and automatic cask updates during releases.

## 1.0.0 — 2026-08-11

### Added

- Added Firebase Analytics to measure aggregate active installations and app launches.
- Added an `app_active` event for tracking LoopBar usage across releases.

### Changed

- Updated the privacy documentation to describe the limited app, session, version, macOS, and device data collected by Firebase.
- Packaged Firebase configuration and analytics support in production DMG builds.

## 0.9.8 — 2026-08-11

### Added

- Added secure Sparkle 2 updates with daily background checks, automatic downloads, and a manual **Check for Updates…** action.
- Added EdDSA-signed appcast generation to the notarized release workflow.

### Changed

- Embedded and Developer ID-sign Sparkle's framework and updater helpers in packaged builds.

### Fixed

- Collapse the expanded island and activate the app before presenting Sparkle dialogs, keeping update results visible and interactive.

## 0.9.7 — 2026-08-11

### Added

- Added a one-command production release pipeline that builds, Developer ID-signs, notarizes, staples, validates, and checksums the DMG.
- Added first-launch installation guidance and production-aware Launch at Login setup.

### Changed

- Redesigned Settings with clearer monitored-app and app-behavior groups, progressive disclosure for advanced controls, and consistently right-aligned switches.
- Refined agent rows with source-first icons and restrained source-colored gradients while keeping semantic colors focused on status pills and attention indicators.
- Smoothed island resizing, content transitions, list updates, hover feedback, and progress changes.
- Added Reduce Motion handling, keyboard-accessible agent rows, and clearer accessibility labels.

### Fixed

- Fixed strict Developer ID signing by keeping SwiftPM's generated resource bundle out of the packaged app root.
- Added automatic synchronization of `CFBundleShortVersionString` and incrementation of `CFBundleVersion` during production releases.

## Feature overview

LoopBar is a native macOS notch-island monitor for local Cursor, Codex, and Claude Code work. It is read-only and requires no API keys. Network access is limited to anonymous usage analytics and signed app updates.

## Island UI

- Notch-aligned floating island centered on the active screen.
- Fully black, opaque background that blends into the screen notch.
- Custom top shoulder curves and rounded bottom corners.
- Compact/minimized mode with a small, notch-safe header.
- Expanded/maximized mode with the agent list, settings, footer actions, and errors.
- Smooth horizontal width animation while the island remains vertically attached to the notch.
- Entire compact island header is clickable, including the empty center gap.
- Directional upper-corner gradients that remain soft and unobtrusive.
- Compact mode hides titles and elapsed time to keep the island readable.

## Compact mode counts

- Left count shows agents currently marked `Running`.
- Right count shows agents that need attention: approval, input, blocked, or failed.
- Queued and unknown agents are not included in the attention count.
- Running colors match the source: Codex blue and Cursor purple.
- When both sources are running, blue is used as the shared accent.
- Attention colors distinguish approval/input, blocked, and failed states.
- Green is reserved for completed agents in the expanded list.

## Expanded agent list

- Shows up to three recent Cursor composers and three recent Codex tasks.
- Combines both sources into one globally sorted list.
- Prioritizes attention states, then running, queued, unknown, and terminal states.
- Shows task title, source label, icon, latest status text, and status badge.
- Displays live elapsed labels such as `Running · 4m` and `Completed · 2m ago`.
- Shows a progress bar when a running agent provides progress information.
- Clickable rows open the related source application.
- Codex rows open the specific task through `codex://threads/<id>` when available.
- Cursor rows open the associated workspace because Cursor does not expose a stable composer deep link.

## Cursor monitoring

- Reads Cursor's live `composerHeaders` table from `state.vscdb`.
- Joins lightweight headers with `cursorDiskKV` composer data.
- Ignores archived, draft, and subagent composers.
- Detects active generation, continuation, worktree application/creation/undo, queues, plans, unread messages, blocked actions, and completion subtitles.
- Uses macOS filesystem events to refresh as soon as Cursor state changes.
- Caches transcript paths and reads only newly appended turn events.
- Uses a 15-second fallback window and a Cursor-open process guard.
- Does not rely on Cursor hooks.

## Codex monitoring

- Reads the local `threads` table from `~/.codex/state_5.sqlite`.
- Ignores archived and subagent threads.
- Reads the tail of each rollout JSONL file for task, approval, input, blocked, tool, and completion events.
- Handles stale approval/input markers by allowing newer reasoning, messages, tool calls, or tool output to restore `Running`.
- Preserves the last Codex snapshot when SQLite is temporarily locked or unavailable.

## Statuses and attention

- Supported statuses: running, queued, waiting for approval, waiting for input, blocked, completed, failed, cancelled, and unknown.
- Attention states are waiting for approval, waiting for input, blocked, and failed.
- Completed, failed, and cancelled are terminal states.
- Unknown is used when local evidence is insufficient instead of guessing completion.

## Refresh and settings

- Polling runs continuously with a configurable interval from 1 to 60 seconds.
- Refresh defaults to every second for responsive live updates.
- Cursor and Codex monitoring can be enabled independently.
- Refresh, source toggles, and the selected interval persist in `UserDefaults`.
- The footer provides a manual refresh button.

## Notifications

- Notifies only after the initial snapshot, avoiding startup noise.
- Alerts when an agent completes or newly needs attention.
- Uses native macOS notifications with a default sound in packaged app builds.
- Uses a sound-enabled `osascript` fallback during raw SwiftPM/debug runs.
- Notification clicks open the associated agent application or Codex task.
