#!/bin/bash
# setup_task.sh - Pre-task hook for met_museum_curation_research

set -e

echo "=== Setting up Met Museum Curation Task ==="

# 1. Record Start Time
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 2. Kill Firefox to ensure clean state and DB access
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 3. Locate Firefox Profile
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
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "/home/ga/.mozilla/firefox/default.profile")
fi
echo "$PROFILE_DIR" > /tmp/firefox_profile_path
echo "Using Profile: $PROFILE_DIR"

# 4. Record Initial Bookmark State
PLACES_DB="$PROFILE_DIR/places.sqlite"
if [ -f "$PLACES_DB" ]; then
    # Snapshot DB to avoid locking
    cp "$PLACES_DB" /tmp/places_baseline.sqlite
    # Count bookmarks (type=1)
    INITIAL_COUNT=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
else
    INITIAL_COUNT=0
fi
echo "$INITIAL_COUNT" > /tmp/initial_bookmark_count

# 5. Clean Previous Artifacts
# Remove output directory and file to prevent false positives from previous runs
rm -rf /home/ga/Documents/met_images
rm -f /home/ga/Documents/exhibition_catalog.json

# Re-create the images directory (agent instruction implies they might need to create it, 
# but creating it empty here is safe and ensures permissions)
sudo -u ga mkdir -p /home/ga/Documents/met_images
sudo -u ga mkdir -p /home/ga/Documents

# 6. Launch Firefox
echo "Launching Firefox..."
# Start with blank page or generic start page
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# Wait for window
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

# Maximize
sleep 2
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="