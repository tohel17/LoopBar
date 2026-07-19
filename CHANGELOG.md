# LoopBar 0.2.0-beta

This beta adds a cleaner, faster notch-island experience for monitoring local Cursor and Codex work.

- Compact island with running and “needs you” counts, designed to stay clear of the notch.
- Expanded agent list with source labels, live status, elapsed time, progress, and clickable rows.
- Source-aware running colors: Codex blue, Cursor purple; completed remains green.
- Stronger directional gradients from the island’s upper corners, with an opaque black background.
- Full-width island click target for reliable expand/collapse behavior.
- Improved Codex detection so stale approval/input events do not hide newer active work.
- Live Cursor composer monitoring from `composerHeaders` and local Codex thread monitoring.
- Status notifications with sound for completed and newly actionable agents.
- Settings for enabling Cursor/Codex sources and choosing the refresh interval.
- Expanded settings spacing and a documented architecture for beta testing.

## Beta notes

LoopBar is read-only and uses local Cursor/Codex metadata. Cursor clicks open the associated workspace; Codex clicks open the specific thread when a deep link is available.
