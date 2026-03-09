#!/bin/bash
# setup_task.sh - Pre-task hook for fred_labor_market_analysis

set -e
echo "=== Setting up FRED Labor Market Analysis Task ==="

# 1. Timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp.txt
echo "Task start time recorded: $(cat /tmp/task_start_timestamp.txt)"

# 2. Kill existing Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 3. Clean up Documents and Downloads to prevent confusion
rm -f /home/ga/Documents/labor_market_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/labor_market_chart.png 2>/dev/null || true
# Also clean likely download names from FRED (e.g., FRED_Graph.csv)
rm -f /home/ga/Downloads/FRED_Graph* 2>/dev/null || true

# 4. Locate Firefox profile (for export script usage later)
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
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path.txt
    echo "Identified Firefox profile: $PROFILE_DIR"
else
    echo "WARNING: Could not identify Firefox profile. verification might be limited."
fi

# 5. Create Documents directory if it doesn't exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Downloads

# 6. Launch Firefox to a blank page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox_launch.log 2>&1 &"

# 7. Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done
sleep 5 # Allow full initialization

# 8. Maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 9. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="