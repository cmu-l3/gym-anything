#!/bin/bash
echo "=== Exporting clock_star_meridian_transit result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_START=$(cat /tmp/transit_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/transit_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
LOG_FILE="/home/ga/Desktop/transit_log.txt"

# 1. Take final screenshot
sleep 2
take_screenshot /tmp/transit_end_screenshot.png

# 2. Gracefully terminate Stellarium to flush config.ini
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

# 3. Parse config.ini with Python
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None,
    "lon_rad": None,
    "flag_atmosphere": None,
    "flag_landscape": None,
    "flag_meridian_line": None,
    "time_zone": None,
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

        # Location (radians)
        result["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
        result["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)

        # Display flags
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_meridian_line"] = get_bool('viewing', 'flag_meridian_line', 'false')

        # Timezone
        try:
            result["time_zone"] = cfg.get('localization', 'time_zone')
        except:
            pass

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Count new screenshots
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/transit_start_ts -type f 2>/dev/null | wc -l)
fi

if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi

# 5. Check log file
LOG_EXISTS="false"
LOG_CREATED_DURING_TASK="false"
LOG_CONTENT=""

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
        LOG_CREATED_DURING_TASK="true"
    fi
    # Read up to 1000 chars to avoid huge payload
    LOG_CONTENT=$(head -c 1000 "$LOG_FILE" | tr -d '\000-\011\013\014\016-\037' | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
fi

# 6. Write result JSON
cat > /tmp/transit_result.json << EOF
{
    "task_start": $TASK_START,
    "config_exists": $(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('config_exists', False))" | tr '[:upper:]' '[:lower:]'),
    "lat_rad": $(echo "$CONFIG_JSON" | python3 -c "import sys, json; val=json.load(sys.stdin).get('lat_rad'); print(val if val is not None else 'null')"),
    "lon_rad": $(echo "$CONFIG_JSON" | python3 -c "import sys, json; val=json.load(sys.stdin).get('lon_rad'); print(val if val is not None else 'null')"),
    "flag_atmosphere": $(echo "$CONFIG_JSON" | python3 -c "import sys, json; val=json.load(sys.stdin).get('flag_atmosphere'); print(str(val).lower() if val is not None else 'null')"),
    "flag_landscape": $(echo "$CONFIG_JSON" | python3 -c "import sys, json; val=json.load(sys.stdin).get('flag_landscape'); print(str(val).lower() if val is not None else 'null')"),
    "flag_meridian_line": $(echo "$CONFIG_JSON" | python3 -c "import sys, json; val=json.load(sys.stdin).get('flag_meridian_line'); print(str(val).lower() if val is not None else 'null')"),
    "time_zone": "$(echo "$CONFIG_JSON" | python3 -c "import sys, json; val=json.load(sys.stdin).get('time_zone'); print(val if val is not None else '')")",
    "new_screenshot_count": $FINAL_SS_COUNT,
    "log_exists": $LOG_EXISTS,
    "log_created_during_task": $LOG_CREATED_DURING_TASK,
    "log_content": "$LOG_CONTENT"
}
EOF

chmod 666 /tmp/transit_result.json 2>/dev/null || true
echo "Export complete. Result saved to /tmp/transit_result.json"