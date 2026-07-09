#!/bin/bash
# Setup: raycast_quicklinks_dynamic
# Removes any stale export file, records baseline timestamp.

set -euo pipefail
echo "=== Setup: raycast_quicklinks_dynamic ==="

DESKTOP="/Users/lume/Desktop"
EXPORT_FILE="$DESKTOP/my_quicklinks.json"

# --- 1. Ensure Raycast is running (idempotent) ---
if ! pgrep -x "Raycast" > /dev/null 2>&1; then
    open -a "Raycast" 2>/dev/null || open -b "com.raycast.macos" 2>/dev/null || true
    for i in $(seq 1 15); do
        if pgrep -x "Raycast" > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi
sleep 3

# --- 2. Remove any stale export file ---
rm -f "$EXPORT_FILE" 2>/dev/null || true

# --- 3. Record task start timestamp ---
date +%s > /tmp/raycast_quicklinks_dynamic_start_ts
mkdir -p "$DESKTOP"

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

echo "Task start ts: $(cat /tmp/raycast_quicklinks_dynamic_start_ts)"
echo "Target export: $EXPORT_FILE"
echo "=== Setup complete ==="
