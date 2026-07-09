#!/bin/bash
# Setup: raycast_workspace_orchestrator
# Cleans the target script path; pre-launches Safari/Notes/TextEdit so the
# agent has windows available to manipulate; records baseline timestamp.

set -euo pipefail
echo "=== Setup: raycast_workspace_orchestrator ==="

SCRIPT_DIR="/Users/lume/Documents/Raycast/Script Commands/Workspace"
SCRIPT_FILE="$SCRIPT_DIR/workspace.sh"

# --- 1. Ensure Raycast is running (idempotent) ---
if ! pgrep -x "Raycast" > /dev/null 2>&1; then
    open -a "Raycast" 2>/dev/null || open -b "com.raycast.macos" 2>/dev/null || true
    for i in $(seq 1 15); do
        if pgrep -x "Raycast" > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi
sleep 3

# --- 2. Remove any stale script from previous runs ---
if [ -d "$SCRIPT_DIR" ]; then
    rm -f "$SCRIPT_FILE" 2>/dev/null || true
fi

# --- 4. Record task start timestamp ---
date +%s > /tmp/raycast_workspace_orchestrator_start_ts

# --- 3. Pre-open Safari, Notes, TextEdit so the agent has windows to tile ---
open -a "Safari" 2>/dev/null || true
open -a "Notes" 2>/dev/null || true
open -a "TextEdit" 2>/dev/null || true
sleep 2

# --- 4. Dismiss any macOS permission dialog (retry loop catches late-appearing dialogs) ---
for _i in $(seq 1 6); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        if exists button "Allow" of front window of application process "UserNotificationCenter" then
            click button "Allow" of front window of application process "UserNotificationCenter"
        end if
    end try
end tell
APPLEOF
    sleep 1
done

echo "Task start ts: $(cat /tmp/raycast_workspace_orchestrator_start_ts)"
echo "Target script path: $SCRIPT_FILE"
echo "=== Setup complete ==="
