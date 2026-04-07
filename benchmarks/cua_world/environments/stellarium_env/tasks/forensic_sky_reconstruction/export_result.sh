#!/bin/bash
echo "=== Exporting forensic_sky_reconstruction result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="forensic_sky_reconstruction"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
REPORT_FILE="/home/ga/Desktop/forensic_sky_report.txt"

# Take final screenshot
if type take_screenshot &>/dev/null 2>&1; then
    take_screenshot /tmp/task_final.png
else
    DISPLAY=:1 import -window root "/tmp/task_final.png" 2>/dev/null || \
    DISPLAY=:1 scrot "/tmp/task_final.png" 2>/dev/null || true
fi

# Terminate Stellarium gracefully to flush config
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited cleanly"
        break
    fi
    sleep 1
done

pkill -9 stellarium 2>/dev/null || true
sleep 2

# Parse config.ini
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None,
    "lon_rad": None,
    "flag_atmosphere": None,
    "flag_landscape": None,
    "flag_constellation_drawing": None,
    "flag_constellation_lines": None,
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

        result["lat_rad"] = get_float('location_run_once', 'latitude')
        result["lon_rad"] = get_float('location_run_once', 'longitude')
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_constellation_lines"] = get_bool('viewing', 'flag_constellation_lines', 'false')

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# Count new screenshots
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))
SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/task_start_time.txt -type f 2>/dev/null | wc -l)
fi
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi

# Check report file content
REPORT_EXISTS="false"
REPORT_HAS_VENUS="false"
REPORT_HAS_JUPITER="false"
REPORT_HAS_CASE="false"
REPORT_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if grep -qi "Venus" "$REPORT_FILE" 2>/dev/null; then
        REPORT_HAS_VENUS="true"
    fi
    if grep -qi "Jupiter" "$REPORT_FILE" 2>/dev/null; then
        REPORT_HAS_JUPITER="true"
    fi
    if grep -qi "2023-ASTRO-0441" "$REPORT_FILE" 2>/dev/null; then
        REPORT_HAS_CASE="true"
    fi
fi

# Generate result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << PYEOF > "$TEMP_JSON"
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_start": $TASK_START,
    "config": config,
    "new_screenshot_count": $FINAL_SS_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_size_bytes": $REPORT_SIZE,
    "report_has_venus": $REPORT_HAS_VENUS,
    "report_has_jupiter": $REPORT_HAS_JUPITER,
    "report_has_case": $REPORT_HAS_CASE
}

print(json.dumps(result, indent=2))
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="