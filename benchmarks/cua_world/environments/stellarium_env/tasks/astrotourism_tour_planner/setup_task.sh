#!/bin/bash
echo "=== Setting up astrotourism_tour_planner task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="astrotourism_tour_planner"

# 1. Kill any existing Stellarium instance and set a known starting config
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 2. Write a fresh config with default (non-configured) display settings
mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
if os.path.exists(config_path):
    cfg.read(config_path)

# Ensure sections exist
for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set known starting state (agent must change these)
cfg.set('landscape', 'flag_atmosphere', 'true')        # must turn OFF
cfg.set('landscape', 'flag_landscape', 'true')         # must turn OFF
cfg.set('viewing', 'flag_constellation_drawing', 'false') # must turn ON
cfg.set('viewing', 'flag_constellation_name', 'false')    # must turn ON
cfg.set('stars', 'flag_star_name', 'true')
cfg.set('navigation', 'startup_time_mode', 'now')

# Reset location to Guereins default (agent must change to New Zealand)
cfg.set('location_run_once', 'latitude', '0.8043')     # ~46 deg N
cfg.set('location_run_once', 'longitude', '0.0834')    # ~4.7 deg E
cfg.set('location_run_once', 'altitude', '200')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config reset to default starting state")
PYEOF

chown -R ga:ga /home/ga/.stellarium

# 3. Remove any stale output files
rm -f /home/ga/Desktop/tour_briefing.txt 2>/dev/null || true

# 4. Record baseline screenshot count
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SCREENSHOT_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# 5. Record task start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp recorded"

# 6. Start Stellarium fresh
echo "--- Starting Stellarium ---"
su - ga -c "bash /home/ga/start_stellarium.sh"

# Wait for Stellarium window to appear
ELAPSED=0
while [ $ELAPSED -lt 90 ]; do
    WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "Stellarium window found (WID=$WID)"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 10

# 7. Dismiss any dialogs and maximize
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

DISPLAY=:1 wmctrl -r "Stellarium" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
    DISPLAY=:1 xdotool windowfocus "$WID" 2>/dev/null || true
fi
sleep 2

# 8. Take initial screenshot
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Starting state: atmosphere=ON, ground=ON, constellations=OFF, location=Guereins"
echo "Agent must set location to Aoraki Mackenzie, time to Mar 15 2024 09:00 UTC,"
echo "disable atmosphere/ground, enable constellation lines/names, and screenshot targets."