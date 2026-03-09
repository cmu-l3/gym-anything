#!/bin/bash
# setup_task.sh - Pre-task hook for dblp_bibtex_research

set -e
echo "=== Setting up dblp_bibtex_research task ==="

# Source utilities
source /workspace/utils/task_utils.sh 2>/dev/null || true

# 1. Kill Firefox and clear state
echo "Killing Firefox..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 3. Clean up previous artifacts
rm -f /home/ga/Documents/deep_learning.bib
# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 4. Find Firefox Profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# If not found, try dynamic search
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
# Fallback
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
fi
echo "$PROFILE_DIR" > /tmp/firefox_profile_path
echo "Using Firefox profile: $PROFILE_DIR"

# 5. Record initial bookmark count
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BOOKMARK_COUNT=0
if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to avoid locks
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null || true
    INITIAL_BOOKMARK_COUNT=$(sqlite3 /tmp/places_baseline.sqlite \
        "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
fi
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count

# 6. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window detected."
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

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="