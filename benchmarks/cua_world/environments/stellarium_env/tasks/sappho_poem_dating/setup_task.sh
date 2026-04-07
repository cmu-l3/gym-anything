#!/bin/bash
echo "=== Setting up sappho_poem_dating task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="sappho_poem_dating"

# 1. Kill Stellarium
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 2. Set default config (Paris, Atmosphere ON, Grid/Art OFF)
# The agent will have to actively change all of these
mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || touch /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
if os.path.exists(config_path):
    cfg.read(config_path)

for section in ['main', 'landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Start state: agent must disable atmosphere, enable azimuthal grid, enable art
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('viewing', 'flag_constellation_art', 'false')

# Start state: Paris. Agent must change location
cfg.set('location_run_once', 'latitude', '0.8527')
cfg.set('location_run_once', 'longitude', '0.0410')
cfg.set('location_run_once', 'altitude', '35')

# Require explicit save via F2 -> "Save settings"
cfg.set('main', 'save_settings_on_exit', 'false')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set to defaults. Agent must configure and explicitly save.")
PYEOF

chown -R ga:ga /home/ga/.stellarium

# 3. Clean up potential stale files
rm -f /home/ga/Desktop/sappho_lecture.txt 2>/dev/null || true

SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# Timestamp for anti-gaming detection
date +%s > /tmp/${TASK_NAME}_start_ts

# 4. Start Stellarium
echo "--- Starting Stellarium ---"
su - ga -c "bash /home/ga/start_stellarium.sh"

ELAPSED=0
while [ $ELAPSED -lt 90 ]; do
    WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "Stellarium window found"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 10

for i in 1 2; do
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

# 5. Take initial screenshot
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="