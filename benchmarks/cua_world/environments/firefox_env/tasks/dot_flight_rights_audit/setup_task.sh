#!/bin/bash
# setup_task.sh - Pre-task hook for dot_flight_rights_audit

set -e
echo "=== Setting up dot_flight_rights_audit task ==="

# 1. Kill Firefox to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Identify Profile
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
echo "Using Profile: $PROFILE_DIR"

# 3. Snapshot Bookmarks (for differential check)
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BM_COUNT=0
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" /tmp/places_init.sqlite
    INITIAL_BM_COUNT=$(sqlite3 /tmp/places_init.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_init.sqlite
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count

# 4. Clean Directories (remove old artifacts)
rm -f /home/ga/Documents/airline_rights_audit.json
rm -f /home/ga/Downloads/*.pdf
mkdir -p /home/ga/Documents /home/ga/Downloads
chown -R ga:ga /home/ga/Documents /home/ga/Downloads

# 5. Timestamp
date +%s > /tmp/task_start_time.txt

# 6. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done
sleep 2

# Maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="