#!/bin/bash
# setup_task.sh - Pre-task hook for noaa_tide_transit_planning

set -e
echo "=== Setting up NOAA Tide Transit Planning task ==="

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# Kill any existing Firefox instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Locate Firefox profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# If no profile found with places.sqlite, look deeper
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

# Fallback
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
    echo "WARNING: Could not find existing places.sqlite, assuming default: $PROFILE_DIR"
fi
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# Record initial bookmark count
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BOOKMARK_COUNT=0
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null || true
    INITIAL_BOOKMARK_COUNT=$(sqlite3 /tmp/places_baseline.sqlite \
        "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
fi
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count

# Clear any previous output file
rm -f /home/ga/Documents/barge_schedule.json 2>/dev/null || true
mkdir -p /home/ga/Documents

# Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'about:blank' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
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

# Focus Firefox
sleep 3
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="