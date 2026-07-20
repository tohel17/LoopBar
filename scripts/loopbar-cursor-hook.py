#!/usr/bin/env python3
"""Record Cursor lifecycle events for LoopBar without touching Cursor's DB."""
import json
import os
import sys
import time

event = sys.argv[1] if len(sys.argv) > 1 else "unknown"
try:
    payload = json.load(sys.stdin)
except Exception:
    payload = {}

def find_value(value, key):
    if isinstance(value, dict):
        if key in value and value[key]:
            return value[key]
        for child in value.values():
            found = find_value(child, key)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = find_value(child, key)
            if found:
                return found
    return None

transcript = find_value(payload, "transcript_path")
session_id = find_value(payload, "session_id")
composer_id = os.path.basename(transcript or "").removesuffix(".jsonl") or session_id
if not composer_id:
    sys.exit(0)

if event in {"beforeShellExecution", "beforeMCPExecution", "preToolUse"}:
    status = "waitingForApproval"
elif event in {"sessionStart", "afterAgentResponse", "afterAgentThought", "afterShellExecution", "afterMCPExecution", "postToolUse"}:
    status = "running"
else:
    status = "completed"
state_path = os.path.expanduser("~/.cursor/loopbar-agent-events.jsonl")
os.makedirs(os.path.dirname(state_path), exist_ok=True)
record = {"id": composer_id, "status": status, "updatedAt": time.time()}
with open(state_path, "a", encoding="utf-8") as state:
    state.write(json.dumps(record, separators=(",", ":")) + "\n")

# Command hooks must return valid JSON. This hook is observational and fails open.
print(json.dumps({}))
