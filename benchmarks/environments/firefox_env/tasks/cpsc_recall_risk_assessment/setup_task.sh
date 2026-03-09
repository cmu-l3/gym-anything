#!/bin/bash
# setup_task.sh - Pre-task hook for cpsc_recall_risk_assessment
# Prepares Firefox and file system for CPSC research task

set -e

echo "=== Setting up cpsc_recall_risk_assessment task ==="

# 1. Kill any existing Firefox instances to ensure clean state
echo "Killing any existing Firefox instances..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Locate Firefox profile (Standard or Snap)
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# Fallback search if standard paths fail
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "/home/ga/.mozilla/firefox/default.profile")
fi
echo "Using Firefox profile: $PROFILE_DIR"
# Save profile path for export script
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 3. Record initial state (Bookmarks)
# We need to know if the user actually adds bookmarks during the task
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BOOKMARK_COUNT=0
if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to avoid locks
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null || true
    if [ -f "/tmp/places_baseline.sqlite" ]; then
        INITIAL_BOOKMARK_COUNT=$(sqlite3 /tmp/places_baseline.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        rm -f /tmp/places_baseline.sqlite
    fi
fi
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count
echo "Initial bookmark count: $INITIAL_BOOKMARK_COUNT"

# 4. Record Task Start Timestamp (Critical for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 5. Clean up output directory
sudo -u ga mkdir -p /home/ga/Documents /home/ga/Downloads
rm -f /home/ga/Documents/cpsc_risk_assessment.json 2>/dev/null || true

# 6. Launch Firefox
# Start with a neutral page to ensure no history pollution
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 7. Wait for Firefox to be ready
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window detected after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Give it a few more seconds to settle
sleep 4

# 8. Maximize and focus window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="