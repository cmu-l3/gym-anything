#!/bin/bash
# setup_task.sh - Pre-task hook for oer_textbook_curriculum_sourcing

set -e
echo "=== Setting up OER Textbook Sourcing Task ==="

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# Kill any running Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Find the active Firefox profile
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
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

if [ -z "$PROFILE_DIR" ]; then
    echo "WARNING: Firefox profile not found. Using default path."
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
    mkdir -p "$PROFILE_DIR"
fi
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# Record initial bookmark state
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BM_COUNT=0
if [ -f "$PLACES_DB" ]; then
    # Use temp copy to avoid locks
    cp "$PLACES_DB" /tmp/places_setup.sqlite
    INITIAL_BM_COUNT=$(sqlite3 /tmp/places_setup.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_setup.sqlite
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count

# Clean up output directories to ensure files are new
rm -f /home/ga/Documents/oer_report.json 2>/dev/null || true
# Clean downloads (optional: might want to keep existing, but for this task specific clean is safer)
rm -f /home/ga/Downloads/*.pdf 2>/dev/null || true

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents /home/ga/Downloads

# Launch Firefox on blank page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
TIMEOUT=45
for i in $(seq 1 $TIMEOUT); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null; then
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

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="