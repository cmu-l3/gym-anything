#!/bin/bash
# setup_task.sh - Pre-task hook for astronomy_observation_planning

set -e
echo "=== Setting up Astronomy Observation Planning task ==="

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure directory structure
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Downloads

# Remove any previous output file
rm -f /home/ga/Documents/stargazing_plan.json

# Kill any existing Firefox instances
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
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

echo "Using Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# Record initial bookmark count
INITIAL_BOOKMARKS=0
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to avoid lock issues
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_baseline.sqlite 2>/dev/null || true
    INITIAL_BOOKMARKS=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
fi
echo "$INITIAL_BOOKMARKS" > /tmp/initial_bookmark_count

# Launch Firefox (starts blank)
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
TIMEOUT=45
for i in $(seq 1 $TIMEOUT); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="