#!/bin/bash
# setup_task.sh - Pre-task hook for rfc_protocol_research

set -e
echo "=== Setting up rfc_protocol_research task ==="

# 1. Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 2. Kill Firefox to ensure clean state and DB access
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 3. Locate Firefox profile
# The env setup creates a specific profile structure
PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
if [ ! -d "$PROFILE_DIR" ]; then
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

if [ -z "$PROFILE_DIR" ]; then
    echo "WARNING: Could not locate Firefox profile. Creating default path."
    mkdir -p "/home/ga/.mozilla/firefox/default.profile"
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
fi
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 4. Clean up previous artifacts
rm -f /home/ga/Documents/rfc_reference.json 2>/dev/null || true
mkdir -p /home/ga/Documents

# 5. Record initial bookmark count (baseline)
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BM_COUNT=0
if [ -f "$PLACES_DB" ]; then
    # Snapshot DB to temp to avoid locks
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null
    if [ -f /tmp/places_baseline.sqlite ]; then
        INITIAL_BM_COUNT=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        rm -f /tmp/places_baseline.sqlite
    fi
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count

# 6. Launch Firefox
echo "Launching Firefox..."
# Use su to run as ga user, pointing to the default profile
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# 7. Wait for window
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# 8. Maximize and focus
sleep 2
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 9. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="