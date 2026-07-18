# LoopBar: live composerHeaders data source

## Problem

`conversation-search.db` is a lagging search index. On this machine its newest row can be a day behind. Today’s chats and agents live in Cursor’s `state.vscdb` `composerHeaders` table.

## Decision

Read the three most recent non-archived, non-subagent rows from `composerHeaders` (agents, chats, and plans). Keep the existing 2-minute recency heuristic for running vs unknown.

## Source

- Path: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
- Table: `composerHeaders`
- Filter: `isArchived = 0 AND isSubagent = 0`
- Order: `COALESCE(lastUpdatedAt, recency, createdAt) DESC`
- Title: `value.name`, else `value.subtitle`, else `"Untitled local agent"`
- Timestamp: `value.lastUpdatedAt`, else column `lastUpdatedAt` / `recency` / `createdAt`

## Non-goals

- No durable run-state parsing beyond the existing recency heuristic
- No writes to Cursor databases
- No ItemTable hybrid merge
