#!/bin/bash
# Setup: raycast_snippet_placeholders_live
# Cleans stale outputs; records baseline; also records today's YYYY-MM-DD
# so the verifier knows what to expect (date may differ from the verifier's
# host clock).

set -euo pipefail
echo "=== Setup: raycast_snippet_placeholders_live ==="

DESKTOP="/Users/lume/Desktop"
EXPANSION_FILE="$DESKTOP/snippet_test.txt"
SNIP_EXPORT="$DESKTOP/snippets_live.raycastsnippets"

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
rm -f "$EXPANSION_FILE" "$SNIP_EXPORT" 2>/dev/null || true

# --- 3. Record baseline timestamp and today's date (machine local) ---
date +%s         > /tmp/raycast_snippet_placeholders_live_start_ts
date +%Y-%m-%d   > /tmp/raycast_snippet_placeholders_live_today
mkdir -p "$DESKTOP"

# --- 4. Clear clipboard so the agent's later copy is clearly new ---
echo -n "" | pbcopy 2>/dev/null || true

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

echo "Task start ts: $(cat /tmp/raycast_snippet_placeholders_live_start_ts)"
echo "Today's date:  $(cat /tmp/raycast_snippet_placeholders_live_today)"
echo "=== Setup complete ==="
