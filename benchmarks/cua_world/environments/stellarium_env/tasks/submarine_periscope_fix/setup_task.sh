#!/bin/bash
echo "=== Setting up submarine_periscope_fix task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="submarine_periscope_fix"

# Record task start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Kill existing Stellarium instances
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# Write a fresh config with default settings
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true
mkdir -p /home/ga/.stellarium
chown ga:ga /home/ga/.stellarium

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
if not os.path.exists(config_path):
    with open(config_path, 'w') as f:
        f.write("")

cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once', 'init_location']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set starting states that the agent must change
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('viewing', 'flag_constellation_drawing', 'false')

# Default location (Pittsburgh)
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')
cfg.set('init_location', 'latitude', '0.705822')
cfg.set('init_location', 'longitude', '-1.396192')
cfg.set('init_location', 'altitude', '367')

with open(config_path, 'w') as f:
    cfg.write(f)
PYEOF
chown ga:ga /home/ga/.stellarium/config.ini

# Remove stale output files
rm -f /home/ga/Desktop/periscope_fix_plan.txt 2>/dev/null || true

# Record initial screenshot count
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# Start Stellarium
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
# Dismiss dialogs
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

take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="