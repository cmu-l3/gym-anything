#!/bin/bash
# Setup: raycast_window_layout_reading
# Quits Safari + Notes so the agent starts from a clean state; ensures Raycast
# is running; dismisses any permission dialog; records baseline timestamp.

set -euo pipefail
echo "=== Setup: raycast_window_layout_reading ==="

# --- 1. Ensure Raycast is running (idempotent) ---
if ! pgrep -x "Raycast" > /dev/null 2>&1; then
    open -a "Raycast" 2>/dev/null || open -b "com.raycast.macos" 2>/dev/null || true
    for i in $(seq 1 15); do
        if pgrep -x "Raycast" > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi
sleep 3

# --- 2. Quit Safari and Notes so the agent starts clean ---
osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
osascript -e 'tell application "Notes" to quit'  2>/dev/null || true
sleep 2

# --- 3. Record task start timestamp ---
date +%s > /tmp/raycast_window_layout_reading_start_ts

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

echo "Task start ts: $(cat /tmp/raycast_window_layout_reading_start_ts)"
echo "=== Setup complete ==="
