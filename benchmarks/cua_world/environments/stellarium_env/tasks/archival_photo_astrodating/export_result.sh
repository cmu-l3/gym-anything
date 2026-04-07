#!/bin/bash
echo "=== Exporting archival_photo_astrodating result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="archival_photo_astrodating"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
EXHIBIT_NOTES="/home/ga/Desktop/moonrise_exhibit_notes.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# 1. Take final screenshot (while Stellarium is still running)
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Gracefully terminate Stellarium to force config.ini save
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited after ${i}s"
        break
    fi
    sleep 1
done

# Force kill if still running
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
    "flag_azimuthal_grid": None,
    "flag_meridian_line": None,
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

        # Stellarium saves location to [init_location] when saving default settings
        if cfg.has_option('init_location', 'latitude'):
            result["lat_rad"] = get_float('init_location', 'latitude', 0.0)
            result["lon_rad"] = get_float('init_location', 'longitude', 0.0)
        else:
            result["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
            result["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)

        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'false')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'false')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_meridian_line"] = get_bool('viewing', 'flag_meridian_line', 'false')

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
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi

if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi

# 5. Check exhibit notes file
NOTES_EXISTS="false"
HAS_YEAR="false"
HAS_MONTH="false"
HAS_LOC="false"
HAS_MOON="false"

if [ -f "$EXHIBIT_NOTES" ]; then
    NOTES_EXISTS="true"
    grep -qi "1941" "$EXHIBIT_NOTES" && HAS_YEAR="true"
    grep -qi "Nov" "$EXHIBIT_NOTES" && HAS_MONTH="true"
    grep -qi "Hernandez" "$EXHIBIT_NOTES" && HAS_LOC="true"
    grep -qi "Moon" "$EXHIBIT_NOTES" && HAS_MOON="true"
fi

# 6. Write result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "config_data": $CONFIG_JSON,
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": $NOTES_EXISTS,
    "notes_has_year": $HAS_YEAR,
    "notes_has_month": $HAS_MONTH,
    "notes_has_location": $HAS_LOC,
    "notes_has_moon": $HAS_MOON
}
EOF

rm -f /tmp/${TASK_NAME}_result.json
cp "$TEMP_JSON" /tmp/${TASK_NAME}_result.json
chmod 666 /tmp/${TASK_NAME}_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json
echo "=== Export complete ==="