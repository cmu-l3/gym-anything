#!/bin/bash
# setup_task.sh - Pre-task hook for school_lunch_menu_planning

set -e

echo "=== Setting up school_lunch_menu_planning task ==="

# 1. Record task start time for anti-gaming (file freshness checks)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 2. Kill any existing Firefox instances to ensure clean state
echo "Killing existing Firefox..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 3. Locate Firefox profile (Standard or Snap)
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
echo "Using Firefox profile: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 4. Clean up output file location
rm -f /home/ga/Documents/weekly_menu_plan.json 2>/dev/null || true
mkdir -p /home/ga/Documents

# 5. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# 6. Wait for Firefox window
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window detected after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# 7. Maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="