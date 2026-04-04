#!/bin/bash
# setup_task.sh - Pre-task hook for usgs_earthquake_data_analysis

set -e

echo "=== Setting up USGS Earthquake Data Analysis task ==="

# 1. Kill any existing Firefox instances
echo "Killing existing Firefox instances..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 3. Clean up previous run artifacts
echo "Cleaning up previous artifacts..."
rm -f /home/ga/Downloads/earthquake_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/earthquake_analysis.txt 2>/dev/null || true
# Also clean default USGS download names to ensure we catch fresh downloads
rm -f /home/ga/Downloads/query.csv 2>/dev/null || true
rm -f /home/ga/Downloads/query*.csv 2>/dev/null || true

# 4. Ensure directories exist
sudo -u ga mkdir -p /home/ga/Downloads /home/ga/Documents /home/ga/Desktop

# 5. Locate Firefox profile (for bookmark baseline)
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

# 6. Launch Firefox (Blank state)
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 7. Wait for Firefox to be ready
echo "Waiting for Firefox window..."
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window appeared."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# 8. Maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 9. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="