#!/bin/bash
echo "=== Setting up ophiuchus_ecliptic_demo task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="ophiuchus_ecliptic_demo"

# 1. Reset Stellarium to a clean starting state
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 2. Write starting config: atmosphere ON, boundaries OFF, ecliptic OFF
mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
if os.path.exists(config_path):
    cfg = configparser.RawConfigParser()
    cfg.read(config_path)

    for section in ['landscape', 'viewing', 'stars', 'location_run_once']:
        if not cfg.has_section(section):
            cfg.add_section(section)

    # Set default values opposing the task requirements
    cfg.set('landscape', 'flag_atmosphere', 'true')
    cfg.set('viewing', 'flag_constellation_boundaries', 'false')
    cfg.set('viewing', 'flag_constellation_name', 'false')
    cfg.set('viewing', 'flag_ecliptic_line', 'false')
    cfg.set('viewing', 'flag_ecliptic_of_date', 'false')

    # Default location (Pittsburgh)
    cfg.set('location_run_once', 'latitude', '0.705822')
    cfg.set('location_run_once', 'longitude', '-1.396192')
    cfg.set('location_run_once', 'altitude', '367')

    with open(config_path, 'w') as f:
        cfg.write(f)
PYEOF

chown -R ga:ga /home/ga/.stellarium

# 3. Clean up potential stale output files for anti-gaming
rm -f /home/ga/Desktop/ophiuchus_script.txt 2>/dev/null || true
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

date +%s > /tmp/${TASK_NAME}_start_ts

# 4. Start Stellarium
echo "--- Starting Stellarium ---"
su - ga -c "bash /home/ga/start_stellarium.sh"

# Wait for window
ELAPSED=0
while [ $ELAPSED -lt 90 ]; do
    WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 10

# Dismiss startup dialogs
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Stellarium" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
    DISPLAY=:1 xdotool windowfocus "$WID" 2>/dev/null || true
fi
sleep 2

# Take initial state screenshot
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="