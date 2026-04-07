#!/bin/bash
echo "=== Exporting celestial_nav_stars result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="celestial_nav_stars"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NAV_LOG="/home/ga/Desktop/nav_star_log.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# 1. Final Screenshot
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Terminate Stellarium cleanly to flush config.ini
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited after ${i}s"
        break
    fi
    sleep 1
done

pkill -9 stellarium 2>/dev/null || true
sleep 2

# 3. Parse config.ini
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None, "alt_m": None,
    "flag_atmosphere": None, "flag_landscape": None,
    "flag_azimuthal_grid": None, "flag_constellation_drawing": None,
    "flag_cardinal_points": None, "config_error": None
}

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

        def get_float(section, key, default=None):
            try:
                return float(cfg.get(section, key))
            except:
                return default

        result["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
        result["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)
        result["alt_m"] = get_float('location_run_once', 'altitude', 0.0)
        
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_cardinal_points"] = get_bool('landscape', 'flag_cardinal_points', 'false')
        
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Count screenshots
SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -newer /tmp/${TASK_NAME}_start_ts 2>/dev/null | wc -l)
fi
echo "New screenshots counted: $SS_NEW_BY_TIME"

# 5. Check Log File
LOG_EXISTS="false"
LOG_CONTENT=""

if [ -f "$NAV_LOG" ]; then
    LOG_EXISTS="true"
    # Read the first 2KB of the log file to avoid massive strings, but ensure we capture the names
    LOG_CONTENT=$(head -c 2048 "$NAV_LOG" | tr '\n' ' ' | sed 's/"/\\"/g' | sed "s/'/\\\\'/g")
fi

# 6. Write out JSON result
RESULT_FILE="/tmp/${TASK_NAME}_result.json"

python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "flag_cardinal_points": config.get("flag_cardinal_points"),
    "new_screenshot_count": $SS_NEW_BY_TIME,
    "log_exists": "$LOG_EXISTS" == "true",
    "log_content": "$LOG_CONTENT"
}

with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 "$RESULT_FILE"
echo "Exported results to $RESULT_FILE"
cat "$RESULT_FILE"