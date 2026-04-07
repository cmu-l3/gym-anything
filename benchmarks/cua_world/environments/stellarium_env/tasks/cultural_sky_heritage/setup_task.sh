#!/bin/bash
echo "=== Setting up cultural_sky_heritage task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="cultural_sky_heritage"

# 1. Kill Stellarium and set known starting state
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 2. Write starting config:
# Atmosphere ON, landscape ON, lines OFF, names OFF, culture western
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
if not os.path.exists(config_path):
    with open(config_path, 'w') as f:
        f.write("")

cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once', 'localization']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set starting state (forces agent to actually do the work):
cfg.set('landscape', 'flag_atmosphere', 'true')           # must turn OFF
cfg.set('landscape', 'flag_landscape', 'true')            # must turn OFF
cfg.set('viewing', 'flag_constellation_drawing', 'false') # must turn ON
cfg.set('viewing', 'flag_constellation_name', 'false')    # must turn ON
cfg.set('localization', 'sky_culture', 'western')         # must end up as egyptian

# Reset location to Pittsburgh default
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set: atmosphere=ON, landscape=ON, lines=OFF, names=OFF, culture=western")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# 3. Remove stale output files
rm -f /home/ga/Desktop/exhibit_sky_notes.txt 2>/dev/null || true

# 4. Record baseline screenshot count
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SS_COUNT"

# 5. Record task start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts

# 6. Start Stellarium
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

# 7. Take initial screenshot
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="