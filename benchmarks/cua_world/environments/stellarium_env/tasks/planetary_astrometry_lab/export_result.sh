#!/bin/bash
echo "=== Exporting planetary_astrometry_lab result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="planetary_astrometry_lab"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_ss_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
LAB_KEY="/home/ga/Desktop/astrometry_key.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# 1. Take final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Gracefully terminate Stellarium to save config
echo "Terminating Stellarium to flush config..."
pkill -SIGTERM stellarium 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

pkill -9 stellarium 2>/dev/null || true
sleep 2

# 3. Read config.ini state and the text file into JSON
python3 << PYEOF
import configparser
import json
import os

config_path = "$CONFIG_PATH"
lab_key_path = "$LAB_KEY"
task_start = $TASK_START
screenshot_dir = "$SCREENSHOT_DIR"

result = {
    "config_exists": False,
    "flag_atmosphere": None,
    "flag_landscape": None,
    "flag_equatorial_grid": None,
    "lab_key_exists": False,
    "lab_key_content": "",
    "new_screenshot_count": 0
}

# Parse Config
if os.path.exists(config_path):
    result["config_exists"] = True
    try:
        cfg = configparser.RawConfigParser()
        cfg.read(config_path)

        def get_bool(section, key, default='false'):
            try:
                return cfg.get(section, key).lower().strip() == 'true'
            except:
                return default.lower() == 'true'

        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_equatorial_grid"] = get_bool('viewing', 'flag_equatorial_grid', 'false')
    except Exception as e:
        result["config_error"] = str(e)

# Read Lab Key
if os.path.exists(lab_key_path):
    result["lab_key_exists"] = True
    try:
        with open(lab_key_path, 'r', encoding='utf-8') as f:
            # Read up to 10KB to prevent bloating JSON
            result["lab_key_content"] = f.read(10240)
    except Exception as e:
        result["lab_key_error"] = str(e)

# Count Screenshots
new_screenshots = 0
if os.path.exists(screenshot_dir):
    for f in os.listdir(screenshot_dir):
        fp = os.path.join(screenshot_dir, f)
        if os.path.isfile(fp):
            mtime = os.path.getmtime(fp)
            if mtime > task_start:
                new_screenshots += 1

result["new_screenshot_count"] = new_screenshots

# Save JSON safely
with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "Export Complete. Result saved to /tmp/${TASK_NAME}_result.json"