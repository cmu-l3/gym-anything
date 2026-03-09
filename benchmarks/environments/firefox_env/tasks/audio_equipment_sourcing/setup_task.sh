#!/bin/bash
# setup_task.sh - Pre-task hook for audio_equipment_sourcing

set -e
echo "=== Setting up Audio Equipment Sourcing Task ==="

# 1. Record start timestamp for anti-gaming (file freshness checks)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 2. Kill any running Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 3. Identify Firefox profile directory
PROFILE_DIR=""
# Check common locations
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

# 4. Record initial state (bookmarks count)
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BOOKMARKS=0
if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to avoid locks
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null
    INITIAL_BOOKMARKS=$(sqlite3 /tmp/places_baseline.sqlite \
        "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
fi
echo "$INITIAL_BOOKMARKS" > /tmp/initial_bookmark_count

# 5. Clean up previous run artifacts (if any)
rm -f /home/ga/Documents/mic_specs.json 2>/dev/null || true
# Note: We don't delete Downloads generally, but we can check freshness later.

# 6. Ensure required directories exist
sudo -u ga mkdir -p /home/ga/Downloads /home/ga/Documents /home/ga/Desktop

# 7. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# 8. Wait for Firefox to be ready
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
sleep 3

# 9. Maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 10. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="