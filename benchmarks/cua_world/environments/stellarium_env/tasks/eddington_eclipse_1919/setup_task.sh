#!/bin/bash
echo "=== Setting up eddington_eclipse_1919 task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="eddington_eclipse_1919"

# Kill Stellarium to ensure a clean start
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# Reset config.ini to default state
mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Default starting state (Agent must modify these)
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('viewing', 'flag_constellation_drawing', 'false')
cfg.set('stars', 'flag_star_name', 'false')
cfg.set('navigation', 'startup_time_mode', 'now')

# Reset location to a default (Pittsburgh)
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')

with open(config_path, 'w') as f:
    cfg.write(f)
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# Clear stale output files
rm -f /home/ga/Desktop/eddington_eclipse.txt 2>/dev/null || true

# Record initial screenshot count
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# Record task start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts

# Start Stellarium
su - ga -c "bash /home/ga/start_stellarium.sh"

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

# Dismiss any potential dialogs
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

DISPLAY=:1 wmctrl -r "Stellarium" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Initial screenshot
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="