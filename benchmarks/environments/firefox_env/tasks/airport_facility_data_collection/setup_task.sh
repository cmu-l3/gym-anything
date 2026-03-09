#!/bin/bash
# setup_task.sh - Pre-task hook for airport_facility_data_collection

set -e
echo "=== Setting up Airport Facility Data Collection Task ==="

# 1. Kill Firefox to ensure clean state
echo "Terminating Firefox..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Record Task Start Time (for file freshness checks)
date +%s > /tmp/task_start_timestamp
echo "Task start time recorded: $(cat /tmp/task_start_timestamp)"

# 3. Clean up previous artifacts
echo "Cleaning up old files..."
rm -f /home/ga/Documents/airport_briefing.json 2>/dev/null || true
rm -f /home/ga/Downloads/*.pdf 2>/dev/null || true
rm -f /home/ga/Downloads/*.PDF 2>/dev/null || true

# 4. Locate Firefox Profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done
# Fallback search
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "/home/ga/.mozilla/firefox/default.profile")
fi
echo "$PROFILE_DIR" > /tmp/firefox_profile_path
echo "Using Firefox profile: $PROFILE_DIR"

# 5. Record initial state (bookmark count)
INITIAL_BOOKMARK_COUNT=0
if [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_baseline.sqlite 2>/dev/null || true
    if [ -f /tmp/places_baseline.sqlite ]; then
        INITIAL_BOOKMARK_COUNT=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        rm -f /tmp/places_baseline.sqlite
    fi
fi
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count

# 6. Ensure directories exist
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Downloads
chown -R ga:ga /home/ga/Documents /home/ga/Downloads

# 7. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done
sleep 3

# Maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="