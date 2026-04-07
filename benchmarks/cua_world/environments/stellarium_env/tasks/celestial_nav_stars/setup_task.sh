#!/bin/bash
echo "=== Setting up celestial_nav_stars task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="celestial_nav_stars"

# 1. Reset Stellarium State
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 2. Write a clean starting config.ini (forcing agent to configure it)
# Start state: Atmosphere OFF, Landscape ON, Constellation lines OFF, Azimuthal OFF, Cardinal OFF
# Agent must: turn Atmosphere ON, Landscape OFF, Constellation lines ON, Azimuthal ON, Cardinal ON
mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
if os.path.exists(config_path):
    cfg = configparser.RawConfigParser()
    cfg.read(config_path)

    for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
        if not cfg.has_section(section):
            cfg.add_section(section)

    cfg.set('landscape', 'flag_atmosphere', 'false')        # Must turn ON
    cfg.set('landscape', 'flag_landscape', 'true')          # Must turn OFF
    cfg.set('landscape', 'flag_cardinal_points', 'false')   # Must turn ON
    cfg.set('viewing', 'flag_azimuthal_grid', 'false')      # Must turn ON
    cfg.set('viewing', 'flag_equatorial_grid', 'false')
    cfg.set('viewing', 'flag_constellation_drawing', 'false') # Must turn ON
    cfg.set('viewing', 'flag_constellation_art', 'false')
    
    # Generic location (Pittsburgh)
    cfg.set('location_run_once', 'latitude', '0.705822')
    cfg.set('location_run_once', 'longitude', '-1.396192')
    cfg.set('location_run_once', 'altitude', '367')
    
    with open(config_path, 'w') as f:
        cfg.write(f)
    print("Config set to generic starting state.")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# 3. Clean up stale outputs
rm -f /home/ga/Desktop/nav_star_log.txt 2>/dev/null || true

# 4. Set up screenshots directory and record baseline
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# 5. Record start timestamp
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

# 7. Maximize window & dismiss dialogs
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

# 8. Initial screenshot
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="