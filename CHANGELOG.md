# LoopBar — feature list

LoopBar is a native macOS notch-island monitor for local Cursor and Codex work. It is read-only, requires no API keys, and does not make network requests.

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

## Beta release

The current packaged build is `0.2.0-beta` (build 2). It includes the complete feature set listed above and is intended for small-group beta testing.
