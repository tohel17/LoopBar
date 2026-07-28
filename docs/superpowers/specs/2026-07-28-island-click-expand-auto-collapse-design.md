# Island click-expand + leave-hover auto-collapse

**Date:** 2026-07-28  
**Status:** Implemented (not committed)

## Problem

Hover-to-expand feels accidental and noisy. Users prefer an explicit open, with the island closing itself when they move away.

## Goals

- Open only on explicit click (compact header toggle).
- Auto-collapse 2 seconds after the pointer leaves the island.
- While the pointer is over the expanded island, do not collapse.
- Keep settings/agents panes reachable while hovered.

## Non-goals

- Hard timed close while still hovering.
- Resetting the timer on every internal click/scroll.
- Changing notification banners or agent data polling.

## Behavior

| Action | Result |
| --- | --- |
| Click compact header while compact | Expand to derived state (agents / loading / notification) |
| Click compact header while expanded | Collapse to compact; reset content to `.agents` |
| Pointer enters expanded island | Cancel any pending collapse timer |
| Pointer leaves expanded island | Start 2s collapse timer |
| Timer fires and pointer still outside | Collapse to compact; reset content to `.agents` |
| Gear / content selection while compact | Expand as today; same leave-hover auto-close applies |
| Hover while compact | No expand |

## Implementation sketch

1. **`IslandViewModel`**
   - Restore `toggleExpanded()`.
   - Change `setHovered(_:)` so hover never expands; it only cancels/starts the existing 2s `collapseTask` when already expanded.
2. **`CompactIslandView`**
   - Restore the header `Button` that calls `toggleExpanded()`.
3. **`MenuPanelView`**
   - Keep `.onHover` → `setHovered` for the collapse timer only.

## Testing

- Manual: click open → leave → collapses ~2s later.
- Manual: click open → keep pointer inside → stays open.
- Manual: leave briefly then re-enter within 2s → stays open.
- Manual: click open → click header again → collapses immediately.
- If unit tests exist for the view model, cover: hover does not expand; leave schedules collapse; re-enter cancels collapse.

## Out of scope follow-ups

- Configurable collapse delay.
- Click-outside-to-dismiss without waiting for leave timer.
