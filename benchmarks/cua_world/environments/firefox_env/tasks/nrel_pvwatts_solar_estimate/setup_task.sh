#!/bin/bash
# setup_task.sh - Pre-task hook for nrel_pvwatts_solar_estimate

set -e
echo "=== Setting up NREL PVWatts Solar Estimate Task ==="

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous run artifacts
echo "Cleaning up previous artifacts..."
rm -f /home/ga/Documents/solar_production_report.txt 2>/dev/null || true
rm -f /home/ga/Downloads/pvwatts_hourly*.csv 2>/dev/null || true
rm -f /tmp/nrel_task_result.json 2>/dev/null || true

# 3. Ensure directories exist
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Downloads

# 4. Find Firefox profile for baseline recording
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# 5. Record initial bookmark count (baseline)
if [ -n "$PROFILE_DIR" ]; then
    echo "Using profile: $PROFILE_DIR"
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_baseline.sqlite 2>/dev/null || true
    if [ -f /tmp/places_baseline.sqlite ]; then
        INITIAL_BM_COUNT=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        echo "$INITIAL_BM_COUNT" > /tmp/initial_bookmark_count
        rm -f /tmp/places_baseline.sqlite
    fi
    # Save profile path for export script
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path
else
    echo "0" > /tmp/initial_bookmark_count
    echo "WARNING: Could not find Firefox profile"
fi

# 6. Launch Firefox
echo "Launching Firefox..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 firefox --new-instance --no-remote &"

# 7. Wait for window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox" > /dev/null; then
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