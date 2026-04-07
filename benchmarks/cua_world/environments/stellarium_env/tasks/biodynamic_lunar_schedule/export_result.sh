#!/bin/bash
echo "=== Exporting biodynamic_lunar_schedule result ==="

TASK_NAME="biodynamic_lunar_schedule"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_ss_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
SCHEDULE_FILE="/home/ga/Desktop/planting_schedule.txt"

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# ── 1. Take final screenshot before stopping Stellarium ───────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Terminate Stellarium to force saving config.ini ────────────────────────
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

# ── 3. Parse config.ini ───────────────────────────────────────────────────────
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None,
    "flag_atmosphere": None, "flag_landscape": None,
    "flag_constellation_boundaries": None,
    "flag_constellation_drawing": None,
    "flag_constellation_name": None,
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

        result["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
        result["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)
        
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_constellation_boundaries"] = get_bool('viewing', 'flag_constellation_boundaries', 'false')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        
        # Check for both possible naming conventions for labels
        name_1 = get_bool('viewing', 'flag_constellation_name', 'false')
        name_2 = get_bool('viewing', 'flag_constellation_names', 'false')
        result["flag_constellation_name"] = name_1 or name_2

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Count screenshots ──────────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
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

# ── 5. Check planting schedule file ───────────────────────────────────────────
FILE_EXISTS="false"
FILE_HAS_VIRGO="false"
FILE_HAS_DATES="false"
FILE_CONTENTS=""

if [ -f "$SCHEDULE_FILE" ]; then
    FILE_EXISTS="true"
    if grep -qi "Virgo" "$SCHEDULE_FILE" 2>/dev/null; then
        FILE_HAS_VIRGO="true"
    fi
    if grep -qE "17|18|19|20" "$SCHEDULE_FILE" 2>/dev/null; then
        FILE_HAS_DATES="true"
    fi
    # Read the first 500 chars safely
    FILE_CONTENTS=$(head -c 500 "$SCHEDULE_FILE" | sed 's/"/\\"/g' | tr '\n' ' ')
fi

# ── 6. Export to JSON ─────────────────────────────────────────────────────────
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task_start": $TASK_START,
    "config": $CONFIG_JSON,
    "new_screenshot_count": $FINAL_SS_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_has_virgo": $FILE_HAS_VIRGO,
    "file_has_dates": $FILE_HAS_DATES,
    "file_contents_sample": "$FILE_CONTENTS"
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/${TASK_NAME}_result.json