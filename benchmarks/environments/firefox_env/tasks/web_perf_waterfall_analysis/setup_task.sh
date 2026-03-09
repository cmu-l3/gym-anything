#!/bin/bash
# setup_task.sh - Pre-task hook for web_perf_waterfall_analysis

set -e

echo "=== Setting up web_perf_waterfall_analysis task ==="

# 1. Kill any existing Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Prepare directories
# Clean up previous runs to ensure anti-gaming (file freshness checks)
rm -rf /home/ga/Documents/har_exports 2>/dev/null || true
rm -f /home/ga/Documents/performance_report.json 2>/dev/null || true

# Create fresh directories
sudo -u ga mkdir -p /home/ga/Documents/har_exports
sudo -u ga mkdir -p /home/ga/Downloads

# 3. Find Firefox profile
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
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# 4. Record task start timestamp (Critical for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 5. Launch Firefox
# Start with a blank page so the agent has to navigate
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window ready after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
sleep 3

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="