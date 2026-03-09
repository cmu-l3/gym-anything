#!/bin/bash
# setup_task.sh - Pre-task hook for apt_threat_intel_profiles
# Prepares Firefox for APT threat intelligence research task

set -e

echo "=== Setting up apt_threat_intel_profiles task ==="

# Source utilities if available
source /workspace/utils/task_utils.sh 2>/dev/null || true

# Kill any existing Firefox instances
echo "Killing any existing Firefox instances..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Find Firefox profile path
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "/home/ga/.mozilla/firefox/default.profile")
fi
echo "Using Firefox profile: $PROFILE_DIR"

# Record initial bookmark count for baseline
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BOOKMARK_COUNT=0
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null || true
    INITIAL_BOOKMARK_COUNT=$(sqlite3 /tmp/places_baseline.sqlite \
        "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
fi
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count
echo "Initial bookmark count: $INITIAL_BOOKMARK_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
TASK_START=$(cat /tmp/task_start_timestamp)
echo "Task start timestamp: $TASK_START"

# Save profile path for export script
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# Ensure output directories exist
sudo -u ga mkdir -p /home/ga/Desktop /home/ga/Downloads /home/ga/Documents

# Remove any pre-existing report file to prevent false positives
rm -f /home/ga/Desktop/threat_intel_report.txt 2>/dev/null || true

# Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Give Firefox time to fully initialize
sleep 4

# Focus Firefox window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== apt_threat_intel_profiles setup complete ==="
echo "Firefox is running. Agent should research Sandworm and Lazarus Group APT profiles."
