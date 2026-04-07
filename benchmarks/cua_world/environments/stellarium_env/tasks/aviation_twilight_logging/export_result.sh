#!/bin/bash
echo "=== Exporting aviation_twilight_logging result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="aviation_twilight_logging"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
LOG_FILE="/home/ga/Desktop/twilight_log.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# 1. Final screenshot capture (while app is running)
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Terminate Stellarium gracefully to flush config to disk
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait for process to exit cleanly
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited gracefully."
        break
    fi
    sleep 1
done

# Force kill if hung
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 3. Parse config.ini state
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None,
    "lon_rad": None,
    "flag_atmosphere": None,
    "flag_landscape": None,
    "config_error": None
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

        # Try both typical location sections
        lat = get_float('location_run_once', 'latitude')
        if lat is None:
            lat = get_float('location', 'latitude')
            
        lon = get_float('location_run_once', 'longitude')
        if lon is None:
            lon = get_float('location', 'longitude')
            
        result["lat_rad"] = lat
        result["lon_rad"] = lon

        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Count newly generated screenshots
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi

# 5. Extract twilight log data
LOG_EXISTS="false"
LOG_MODIFIED_DURING_TASK="false"
LOG_CONTENT=""

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$LOG_MTIME" -ge "$TASK_START" ]; then
        LOG_MODIFIED_DURING_TASK="true"
    fi
    # Safely extract up to 2KB of text to pass into JSON
    LOG_CONTENT=$(head -c 2048 "$LOG_FILE" | base64 -w 0)
fi

# 6. Build the final JSON
python3 << PYEOF
import json
import base64

config = json.loads('''$CONFIG_JSON''')

log_content_base64 = "$LOG_CONTENT"
try:
    log_text = base64.b64decode(log_content_base64).decode('utf-8', errors='replace')
except:
    log_text = ""

result = {
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "log_exists": "$LOG_EXISTS" == "true",
    "log_modified_during_task": "$LOG_MODIFIED_DURING_TASK" == "true",
    "log_content": log_text
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json

echo "=== Export Complete ==="