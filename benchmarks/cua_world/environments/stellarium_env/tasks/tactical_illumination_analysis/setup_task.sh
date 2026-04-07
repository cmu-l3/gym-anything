#!/bin/bash
echo "=== Setting up tactical_illumination_analysis task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="tactical_illumination_analysis"

# 1. Kill any existing Stellarium process
echo "--- Ensuring Stellarium is closed ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 2. Reset config.ini to a default state (requires agent to make active changes)
mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || touch /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Starting state:
# flag_landscape = true (Agent must turn OFF to see below horizon)
# flag_azimuthal_grid = false (Agent must turn ON to check altitude degrees)
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('navigation', 'startup_time_mode', 'now')

# Set location far away from the target
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)
PYEOF

chown -R ga:ga /home/ga/.stellarium

# 3. Clean up any previous runs output 
rm -f /home/ga/Desktop/illumination_report.txt 2>/dev/null || true

# 4. Record baseline screenshot count for anti-gaming (detects new files vs existing)
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# 5. Record start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts

# 6. Take initial screenshot (Stellarium closed, clean desktop)
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup complete ==="
echo "Agent must launch Stellarium manually, configure coordinates and display parameters."