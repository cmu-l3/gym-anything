#!/bin/bash
# Setup: raycast_quicklink_tab_reuse
# Opens Safari with exactly one tab at the salmon search URL.
# Wipes any stale quicklinks export.

set -euo pipefail
echo "=== Setup: raycast_quicklink_tab_reuse ==="

EXPORT_FILE="/Users/lume/Desktop/my_quicklinks.json"
INITIAL_URL="https://duckduckgo.com/?q=salmon+recipe+2+servings"

# --- 1. Ensure Raycast running + dismiss dialogs ---
if ! pgrep -x "Raycast" > /dev/null 2>&1; then
    open -a "Raycast" 2>/dev/null || true
    for i in $(seq 1 15); do
        if pgrep -x "Raycast" > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi
sleep 3
for _i in $(seq 1 4); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        repeat with proc in (every application process whose frontmost is true)
            tell proc
                if exists button "Allow" of front window then click button "Allow" of front window
                if exists button "OK" of front window then click button "OK" of front window
                if exists button "Don't Allow" of front window then click button "Don't Allow" of front window
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

# --- 2. Wipe stale export ---
rm -f "$EXPORT_FILE" 2>/dev/null || true

# --- 3. Open Safari with exactly one tab at the salmon URL ---
# Quit Safari first to ensure clean state
osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
sleep 2
open -a "Safari" 2>/dev/null || true
sleep 3
# Open the URL in Safari (will create a window+tab)
open -a "Safari" "$INITIAL_URL"
sleep 4

# Close all OTHER tabs in Safari so exactly one remains
osascript << APPLEOF 2>/dev/null || true
tell application "Safari"
    try
        repeat with w in windows
            set tabsToKeep to {}
            set keptOne to false
            repeat with t in tabs of w
                set tu to URL of t
                if tu contains "duckduckgo.com" and tu contains "salmon" and not keptOne then
                    set keptOne to true
                else
                    close t
                end if
            end repeat
        end repeat
    end try
end tell
APPLEOF
sleep 2

# --- 4. Record baseline ---
date +%s > /tmp/raycast_quicklink_tab_reuse_start_ts
echo "Initial Safari URL: $(osascript -e 'tell application "Safari" to get URL of current tab of front window' 2>/dev/null || echo "?")"
echo "=== Setup complete ==="
