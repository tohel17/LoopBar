# LoopBar pending items

Living backlog for beta polish and next features. Each item includes the user
value, intended scope, and a rough definition of done.

## User-requested

### 1. Support Claude agents

LoopBar should monitor Claude-based local agents alongside Cursor and Codex so
the island becomes a single place to see all active coding assistants.

Scope:

- Discover where Claude stores local task/session state.
- Add a Claude data source/service similar to `CursorAPI` and `CodexAPI`.
- Map Claude-specific states into LoopBar's shared statuses: running, queued,
  waiting for approval, waiting for input, blocked, completed, failed, cancelled,
  or unknown.
- Show Claude rows with a distinct source label and visual color.
- Add open/click behavior if Claude exposes a reliable local URL, app route, or
  file/session target.

Done when:

- Claude agents appear in the island with correct title/status.
- Long-running, completed, blocked, and waiting states are recognized reliably.
- Claude can be enabled/disabled independently from Cursor and Codex.

Notes:

- This needs investigation first. Do not assume Claude exposes Codex-like rollout
  logs or Cursor-like SQLite state.

### 2. Ask/respond directly from the island when an agent is blocked

When an agent needs user input, approval, or clarification, LoopBar should let the
user act from the island instead of forcing them to open the full app first.

Scope:

- Detect actionable states: blocked, waiting for approval, waiting for input.
- Expand the affected row into an action area.
- For simple input requests, show a text field and submit button.
- For approval requests, show explicit approve/decline buttons when the source
  supports it.
- Route the response back to the correct Codex/Cursor/Claude task.
- Prevent accidental sends with clear labels and confirmation for risky actions.

Done when:

- A blocked/waiting Codex task can be answered from LoopBar.
- Cursor support is added only if a safe local API/route is found.
- The UI clearly shows what will be sent and to which agent.

Notes:

- Codex is the most likely first source because its task model has explicit
  approval/input events.
- Cursor may be limited if it does not expose a local write API.

## Product polish

### 3. Adaptive refresh

LoopBar currently polls sources at a fixed interval. Adaptive refresh would keep
the app responsive when work is active while reducing unnecessary reads when
nothing is happening.

Scope:

- Poll fast, around 1 second, when any agent is running or needs attention.
- Poll slower, around 5-10 seconds, when all agents are completed, cancelled, or
  unknown.
- Poll fast while the island is expanded so the visible UI feels live.
- Avoid resetting the polling loop too aggressively.

Done when:

- Status changes still appear quickly during active work.
- Idle CPU/disk activity is lower than the fixed 1-second polling mode.
- The refresh setting either becomes an advanced override or defines the maximum
  polling speed.

### 4. Launch at Login

LoopBar is a utility that should be available immediately after login, especially
for beta testers who may forget to launch it manually.

Scope:

- Add a settings toggle: "Launch LoopBar at login".
- Use Apple's `ServiceManagement` login item API where appropriate.
- Persist the user's preference.
- Make the toggle reflect the actual login item state.

Done when:

- Enabling the setting starts LoopBar automatically after macOS login.
- Disabling it removes LoopBar from login items.
- The setting survives app restarts.

### 5. Copy Debug Report

Beta testers need an easy way to report problems without manually finding logs,
database paths, or version information.

Scope:

- Add a button in Settings: "Copy Debug Report".
- Copy a sanitized text report to the clipboard.
- Include app version, macOS version, notification mode, refresh interval, source
  availability, database paths checked, recent error message, and current agent
  snapshot.
- Avoid copying private prompt content or full conversation logs.

Done when:

- A tester can click one button and paste useful diagnostic info into a message.
- The report is safe to share and does not include sensitive conversation text.

### 6. Better Cursor open behavior

Codex now opens the specific task correctly. Cursor currently opens the related
workspace when available, but not the exact composer chat.

Scope:

- Investigate Cursor's actual deep-link or command route for opening a composer
  by `composerId`.
- If no route exists, look for a safe local IPC/extension command path.
- Keep the current workspace-open fallback.
- Update row help text or documentation so the behavior is clear.

Done when:

- Clicking a Cursor row opens the exact composer if Cursor supports it.
- If exact composer opening is impossible, LoopBar reliably opens the correct
  workspace/window and does not pretend otherwise.

### 7. Filter by source

The expanded island should let users narrow the agent list to the source they
care about, especially once Claude support is added.

Scope:

- Add a compact segmented control or pill row: All, Cursor, Codex, and later
  Claude.
- Filter the expanded agent list without affecting the compact global status.
- Persist the selected filter only if it feels useful; otherwise reset to All on
  launch.
- Make empty filtered states clear, for example "No Codex agents".

Done when:

- Users can quickly switch between all agents and a single source.
- Filtering does not break sorting, notifications, or compact counts.
- The UI remains clean inside the notch-sized panel.

### 8. Show elapsed time

Agent rows should show how long an agent has been running or how recently it
finished, so users can understand status at a glance.

Scope:

- Show labels like `Running · 4m`, `Needs approval · 1m`, or `Completed · 2m ago`.
- Prefer source-specific timestamps when available.
- Keep text short enough for the current row layout.
- Update elapsed labels during refresh without introducing heavy timers.

Done when:

- Running and attention states show useful elapsed duration.
- Completed states show relative completion/last-active time.
- The row remains readable and does not wrap awkwardly.

### 9. Group counts in compact island

The compact island should communicate more than just the running count when
there are multiple agent states.

Scope:

- Compute grouped counts such as running, needs you, done, and maybe failed.
- Explore compact text formats like `2 running`, `1 needs you`, `3 done`.
- Prioritize attention counts over completed counts when space is limited.
- Keep the compact island readable when counts become large.

Done when:

- Compact mode gives a better summary of the overall agent situation.
- Attention states are impossible to miss.
- The compact layout still blends cleanly with the notch.

### 10. Attention-only compact mode

When an agent needs the user, compact mode should say that directly instead of
using a vague status like `Check`.

Scope:

- Replace generic `Check` with specific labels where possible:
  `Needs approval`, `Waiting`, `Blocked`, or `Failed`.
- If multiple attention states exist, choose the highest-priority label or show a
  count such as `2 need you`.
- Use stronger color/icon treatment only for actionable states.
- Avoid making normal completed/idle states visually noisy.

Done when:

- A blocked/waiting/approval state is clear from compact mode without expanding.
- Users can tell whether they need to act immediately.
- The compact island still feels calm when nothing needs attention.

### 11. Better beta packaging

The current DMG is functional but very simple. Better packaging will make beta
testing smoother and reduce first-run confusion.

Scope:

- Regenerate the DMG after meaningful beta changes.
- Add a beta README/install note.
- Include Gatekeeper instructions for ad-hoc signed builds.
- Consider an Applications-folder shortcut in the DMG.
- Before wider sharing, consider Developer ID signing and notarization.

Done when:

- Testers can install and launch LoopBar with minimal explanation.
- The DMG clearly communicates that it is a beta build.
- Version/checksum information is easy to verify.

### 12. Notification preferences

Notifications are useful, but users need control over when LoopBar interrupts
them.

Scope:

- Add toggles for completion notifications.
- Add toggles for approval/input/blocked notifications.
- Add toggles for failure notifications.
- Add an optional quiet mode or "only notify when attention is needed" mode.
- Keep debug notification behavior separate from production notification
  behavior.

Done when:

- Users can reduce notification noise without disabling all monitoring.
- Preferences persist across restarts.
- Notifications still work in packaged app mode and debug fallback mode.

### 13. Multi-display/notch QA

LoopBar's core UI depends on precise screen positioning, so it needs testing
across display setups.

Scope:

- Test on notched MacBook displays.
- Test on non-notched displays.
- Test with external monitors attached and disconnected.
- Confirm the island remains top-aligned and centered correctly.
- Confirm expand/minimize width animation stays anchored.

Done when:

- The island appears in a sensible position on all tested display setups.
- Screen changes do not leave the panel floating in the wrong place.
- Any remaining limitations are documented.

## Completed

### Source toggles

Users may not use every supported tool. Source toggles keep LoopBar quiet and
focused for each person.

Implemented:

- Added settings toggles for Cursor and Codex monitoring.
- Disabled sources are skipped during polling.
- Disabled-source errors are hidden from the island.
- Disabled source rows are excluded from compact count/status.

Completed when:

- A user can turn off a source they do not use.
- Disabled sources produce no visible errors or notifications.
- The setting persists across restarts.
