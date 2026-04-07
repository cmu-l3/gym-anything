#!/bin/bash
echo "=== Setting up nocturnal_insect_navigation_plan task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="nocturnal_insect_navigation_plan"

# 1. Kill Stellarium to set a known starting config
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 2. Write starting config: atmosphere ON, grids OFF, location = Pittsburgh
# This ensures the agent must actively make the required changes and save them.
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Start state for insect task:
# atmosphere = ON (must turn OFF)
# azimuthal_grid = OFF (must turn ON)
# galactic_grid = OFF (must turn ON - requires GUI navigation)
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('viewing', 'flag_galactic_grid', 'false')
cfg.set('viewing', 'flag_equatorial_grid', 'false')
cfg.set('viewing', 'flag_constellation_art', 'false')
cfg.set('viewing', 'flag_constellation_drawing', 'false')
cfg.set('stars', 'flag_star_name', 'true')
cfg.set('navigation', 'startup_time_mode', 'now')
cfg.set('navigation', 'preset_sky_time', '2451545.0')

# Reset location to Pittsburgh default
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set: atmosphere=ON, grids=OFF, location=Pittsburgh (agent must configure and save)")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# 3. Remove stale output files
rm -f /home/ga/Desktop/beetle_field_plan.txt 2>/dev/null || true

# 4. Record baseline screenshot count
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
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

# Dismiss startup dialogs
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
echo "Agent must: set location to South Africa (-26.95, 24.73), date to Nov 1 2024 22:00 UTC,"
echo "  disable atmosphere, enable azimuthal grid, enable galactic grid, center on Crux,"
echo "  SAVE settings (F2), take screenshot, write beetle_field_plan.txt."