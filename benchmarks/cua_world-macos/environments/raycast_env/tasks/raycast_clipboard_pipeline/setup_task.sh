#!/bin/bash
# Setup: raycast_clipboard_pipeline
# Cleans stale output files; clears the system clipboard; records baseline.

set -euo pipefail
echo "=== Setup: raycast_clipboard_pipeline ==="

DESKTOP="/Users/lume/Desktop"
CLIP_OUT="$DESKTOP/clipboard_test.txt"
SNIP_OUT="$DESKTOP/snippets.raycastsnippets"

# --- 1. Ensure Raycast is running ---
if ! pgrep -x "Raycast" > /dev/null 2>&1; then
    open -a "Raycast" 2>/dev/null || open -b "com.raycast.macos" 2>/dev/null || true
    for i in $(seq 1 15); do
        if pgrep -x "Raycast" > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi
sleep 3

# --- 2. Remove stale outputs ---
rm -f "$CLIP_OUT" "$SNIP_OUT" 2>/dev/null || true

# --- 3. Clear system clipboard so the agent's copies are clearly new ---
echo -n "" | pbcopy 2>/dev/null || true

# --- 4. Record task start timestamp ---
date +%s > /tmp/raycast_clipboard_pipeline_start_ts
mkdir -p "$DESKTOP"

# --- 5. Dismiss any macOS permission dialog (retry loop catches late-appearing dialogs) ---
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

echo "Task start ts: $(cat /tmp/raycast_clipboard_pipeline_start_ts)"
echo "=== Setup complete ==="
