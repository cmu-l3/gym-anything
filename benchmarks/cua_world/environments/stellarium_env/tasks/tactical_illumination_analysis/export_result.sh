#!/bin/bash
echo "=== Exporting tactical_illumination_analysis result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="tactical_illumination_analysis"
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"

# 1. Take final trajectory screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Terminate Stellarium gracefully to flush config.ini to disk
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        break
    fi
    sleep 1
done
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 3. Calculate new screenshot count
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi

# Use highest valid count
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi
echo "$FINAL_SS_COUNT" > /tmp/${TASK_NAME}_final_ss_count

# 4. Gather task state entirely through Python (prevents text encoding/quoting issues)
python3 << 'PYEOF'
import json
import os
import configparser

task_name = "tactical_illumination_analysis"
config_path = "/home/ga/.stellarium/config.ini"

result = {
    "task_start": 0,
    "lat_rad": None, "lon_rad": None, "alt_m": None,
    "flag_landscape": None, "flag_azimuthal_grid": None,
    "flag_atmosphere": None,
    "new_screenshot_count": 0,
    "report_exists": False,
    "report_content": ""
}

try:
    with open(f"/tmp/{task_name}_start_ts", "r") as f:
        result["task_start"] = int(f.read().strip())
except Exception:
    pass

try:
    with open(f"/tmp/{task_name}_final_ss_count", "r") as f:
        result["new_screenshot_count"] = int(f.read().strip())
except Exception:
    pass

if os.path.exists(config_path):
    cfg = configparser.RawConfigParser()
    cfg.read(config_path)
    
    def get_bool(section, key, default='false'):
        try:
            return cfg.get(section, key).lower().strip() == 'true'
        except Exception:
            return default.lower() == 'true'

    def get_float(section, key, default=None):
        try:
            return float(cfg.get(section, key))
        except Exception:
            return default

    result["lat_rad"] = get_float('location_run_once', 'latitude')
    result["lon_rad"] = get_float('location_run_once', 'longitude')
    result["alt_m"] = get_float('location_run_once', 'altitude')
    result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
    result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
    result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')

report_file = "/home/ga/Desktop/illumination_report.txt"
if os.path.exists(report_file):
    result["report_exists"] = True
    try:
        with open(report_file, "r", encoding="utf-8") as f:
            result["report_content"] = f.read()[:2000] # Caps reading to first 2000 chars for safety
    except Exception:
        pass

with open(f"/tmp/{task_name}_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json
echo "Results exported to /tmp/${TASK_NAME}_result.json"