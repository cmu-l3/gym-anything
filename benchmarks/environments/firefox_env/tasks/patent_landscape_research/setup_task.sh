#!/bin/bash
# setup_task.sh - Pre-task hook for patent_landscape_research

set -e
echo "=== Setting up Patent Landscape Research task ==="

# 1. Kill Firefox to ensure clean state and database access
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Locate Firefox profile
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
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

if [ -n "$PROFILE_DIR" ]; then
    echo "Using Firefox profile: $PROFILE_DIR"
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path
else
    echo "WARNING: Could not find Firefox profile!"
fi

# 3. Record initial bookmark state
INITIAL_BM_COUNT=0
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_init.sqlite
    INITIAL_BM_COUNT=$(sqlite3 /tmp/places_init.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_init.sqlite
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count
echo "Initial bookmarks: $INITIAL_BM_COUNT"

# 4. Clean up previous output
rm -f /home/ga/Documents/patent_landscape.json
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Launch Firefox to blank page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 7. Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 8. Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="