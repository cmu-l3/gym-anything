#!/bin/bash
# setup_task.sh - Pre-task hook for hts_tariff_classification

set -e
echo "=== Setting up HTS Tariff Classification Task ==="

# 1. Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Cleanup previous artifacts to ensure clean state
rm -f /home/ga/Documents/tariff_classification.json
rm -f /tmp/task_result.json

# 3. Ensure target directory exists
mkdir -p /home/ga/Documents

# 4. Prepare Firefox
# Kill any running instances to ensure profile is unlocked
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Locate Firefox profile
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

if [ -n "$PROFILE_DIR" ]; then
    echo "Using Firefox profile: $PROFILE_DIR"
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path
    
    # Snapshot initial bookmark state
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_initial.sqlite
    sqlite3 /tmp/places_initial.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" > /tmp/initial_bookmark_count 2>/dev/null || echo "0" > /tmp/initial_bookmark_count
else
    echo "WARNING: Could not find Firefox profile. Task verification might fail."
    echo "0" > /tmp/initial_bookmark_count
fi

# 5. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote https://hts.usitc.gov/ > /tmp/firefox.log 2>&1 &"

# 6. Wait for window and maximize
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox" > /dev/null; then
        echo "Firefox window detected."
        # Maximize
        DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="