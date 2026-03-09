#!/bin/bash
# setup_task.sh - Pre-task hook for species_conservation_assessment

set -e

echo "=== Setting up species_conservation_assessment task ==="

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# Kill any running Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Find Firefox profile directory
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
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

echo "Using Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# Record initial bookmark count (baseline)
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BOOKMARKS=0
if [ -f "$PLACES_DB" ]; then
    TEMP_DB="/tmp/places_setup_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    if [ -f "$TEMP_DB" ]; then
        INITIAL_BOOKMARKS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        rm -f "$TEMP_DB"
    fi
fi
echo "$INITIAL_BOOKMARKS" > /tmp/initial_bookmark_count

# Ensure Documents directory exists and clean previous output
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/species_assessment.json 2>/dev/null || true

# Launch Firefox with blank page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

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
sleep 3

# Maximize Firefox
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="