#!/bin/bash
# setup_task.sh - Pre-task hook for hud_housing_market_rent_research

set -e
echo "=== Setting up HUD FMR Research Task ==="

# 1. Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 2. Cleanup previous runs
rm -f /home/ga/Documents/fmr_audit_2024.json 2>/dev/null || true
sudo -u ga mkdir -p /home/ga/Documents

# 3. Kill existing Firefox to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 4. Locate Firefox profile
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
echo "Using Profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 5. Record initial bookmark count
PLACES_DB="$PROFILE_DIR/places.sqlite"
INITIAL_BM_COUNT=0
if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to read without locking
    cp "$PLACES_DB" /tmp/places_setup.sqlite 2>/dev/null || true
    if [ -f /tmp/places_setup.sqlite ]; then
        INITIAL_BM_COUNT=$(sqlite3 /tmp/places_setup.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        rm -f /tmp/places_setup.sqlite
    fi
fi
echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count

# 6. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# 7. Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# 8. Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="