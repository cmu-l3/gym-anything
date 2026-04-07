#!/bin/bash
echo "=== Exporting qibla_solar_alignment result ==="

TASK_NAME="qibla_solar_alignment"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
REPORT_FILE="/home/ga/Desktop/qibla_report.txt"

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Take final screenshot
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Kill Stellarium gracefully to flush config
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then break; fi
    sleep 1
done
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 3. Use Python to parse config, read report, and create JSON
python3 << PYEOF
import configparser
import json
import os

result = {
    "task_start": $TASK_START,
    "initial_ss_count": $INITIAL_SS_COUNT,
    "final_ss_count": 0,
    "new_screenshots_count": 0,
    "config_exists": False,
    "lat_rad": None,
    "lon_rad": None,
    "flag_atmosphere": None,
    "flag_azimuthal_grid": None,
    "report_exists": False,
    "report_created_during_task": False,
    "report_content": ""
}

# Check screenshots
ss_dir = "$SCREENSHOT_DIR"
if os.path.exists(ss_dir):
    current_ss = len([f for f in os.listdir(ss_dir) if os.path.isfile(os.path.join(ss_dir, f))])
    result["final_ss_count"] = current_ss
    result["new_screenshots_count"] = max(0, current_ss - $INITIAL_SS_COUNT)

# Check config
config_path = "/home/ga/.stellarium/config.ini"
if os.path.exists(config_path):
    result["config_exists"] = True
    try:
        cfg = configparser.RawConfigParser()
        cfg.read(config_path)
        
        def get_bool(section, key, default='false'):
            try: return cfg.get(section, key).lower().strip() == 'true'
            except: return default.lower() == 'true'
            
        def get_float(section, key, default=None):
            try: return float(cfg.get(section, key))
            except: return default

        result["lat_rad"] = get_float('location_run_once', 'latitude')
        result["lon_rad"] = get_float('location_run_once', 'longitude')
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
    except Exception as e:
        pass

# Check report
report_path = "$REPORT_FILE"
if os.path.exists(report_path):
    result["report_exists"] = True
    try:
        mtime = os.path.getmtime(report_path)
        if mtime >= $TASK_START:
            result["report_created_during_task"] = True
        
        with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
            result["report_content"] = f.read(2048)  # limit to 2KB
    except Exception as e:
        pass

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "Exported result:"
cat /tmp/${TASK_NAME}_result.json
echo -e "\n=== Export Complete ==="