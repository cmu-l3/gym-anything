#!/bin/bash
# setup_task.sh - Pre-task hook for census_telehealth_demographic_study

set -e
echo "=== Setting up Census Telehealth Demographic Study task ==="

# 1. Record task start timestamp for anti-gaming (file freshness checks)
date +%s > /tmp/task_start_timestamp
echo "Task start time: $(cat /tmp/task_start_timestamp)"

# 2. Clean up environment (remove previous artifacts)
echo "Cleaning up previous artifacts..."
rm -f /home/ga/Documents/telehealth_pilot_data.json 2>/dev/null || true

# 3. Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 4. Handle Firefox Profile (for bookmark verification baselining)
# Kill any existing Firefox to unlock DB
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Locate Profile
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
echo "Using Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# Record initial bookmark count
if [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_baseline.sqlite
    sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" > /tmp/initial_bookmark_count 2>/dev/null || echo "0" > /tmp/initial_bookmark_count
    rm -f /tmp/places_baseline.sqlite
else
    echo "0" > /tmp/initial_bookmark_count
fi

# 5. Launch Firefox to a blank page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
TIMEOUT=30
for i in $(seq 1 $TIMEOUT); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected."
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

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="