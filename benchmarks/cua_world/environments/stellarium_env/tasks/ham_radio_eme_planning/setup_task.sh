#!/bin/bash
echo "=== Setting up ham_radio_eme_planning task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="ham_radio_eme_planning"

# 1. Kill any existing Stellarium instance and set a known starting config
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 2. Write a fresh config with default display settings
# Start state: atmosphere=ON, landscape=ON, azimuthal_grid=OFF
# Agent must: turn atmosphere OFF, landscape OFF, azimuthal_grid ON
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
if not os.path.exists(config_path):
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, 'w') as f:
        f.write("")

cfg = configparser.RawConfigParser()
cfg.read(config_path)

# Ensure sections exist
for section in ['landscape', 'viewing', 'location_run_once', 'navigation', 'stars']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set known starting state (default-like)
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('viewing', 'flag_equatorial_grid', 'false')

# Reset location to a neutral default (e.g., Pittsburgh)
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'home_planet', 'Earth')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config reset to default starting state")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# 3. Remove any stale output files so do-nothing tests fail
rm -f /home/ga/Desktop/eme_sked_nov15.txt 2>/dev/null || true

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

# 6. Take initial screenshot (desktop should be empty, Stellarium closed)
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Stellarium is intentionally closed. Agent must launch it."