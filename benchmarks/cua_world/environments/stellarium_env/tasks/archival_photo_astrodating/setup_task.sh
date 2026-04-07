#!/bin/bash
echo "=== Setting up archival_photo_astrodating task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="archival_photo_astrodating"

# 1. Kill any existing Stellarium instance
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 2. Write a fresh config with default (non-configured) display settings
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

# Ensure sections exist
for section in ['landscape', 'viewing', 'init_location', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Start state: atmosphere=OFF, landscape=OFF, grids=OFF
# Agent must turn them all ON
cfg.set('landscape', 'flag_atmosphere', 'false')
cfg.set('landscape', 'flag_landscape', 'false')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('viewing', 'flag_meridian_line', 'false')
cfg.set('viewing', 'flag_equatorial_grid', 'false')

# Reset location to London default (Agent must change to Hernandez, NM)
cfg.set('init_location', 'latitude', '0.8988')
cfg.set('init_location', 'longitude', '-0.0022')
cfg.set('init_location', 'altitude', '11')
cfg.set('init_location', 'name', 'London')
cfg.set('location_run_once', 'latitude', '0.8988')
cfg.set('location_run_once', 'longitude', '-0.0022')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config reset to default starting state")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# 3. Remove any stale output files
rm -f /home/ga/Desktop/moonrise_exhibit_notes.txt 2>/dev/null || true

# 4. Record baseline screenshot count
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

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

# 8. Take initial screenshot
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Starting state: grids=OFF, atmosphere=OFF, ground=OFF, location=London"
echo "Agent must set location to Hernandez NM, date to Nov 1 1941, enable grids/atmosphere/landscape, save settings, and write exhibit notes."