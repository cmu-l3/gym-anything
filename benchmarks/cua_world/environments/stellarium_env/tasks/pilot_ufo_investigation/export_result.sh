#!/bin/bash
echo "=== Exporting pilot_ufo_investigation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="pilot_ufo_investigation"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
REPORT_PATH="/home/ga/Desktop/ufo_investigation_report.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot before killing Stellarium ────────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to flush config.ini ───────────────────
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
    "lat_rad": None, "lon_rad": None, "alt_m": None,
    "flag_atmosphere": None, "flag_landscape": None,
    "flag_planets_labels": None, "flag_cardinal_points": None,
    "preset_sky_time": None, "config_error": None
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
        
        if cfg.has_option('astro', 'flag_planets_labels'):
            result["flag_planets_labels"] = get_bool('astro', 'flag_planets_labels', 'true')
        elif cfg.has_option('gui', 'flag_show_planets_names'):
            result["flag_planets_labels"] = get_bool('gui', 'flag_show_planets_names', 'true')
        else:
            result["flag_planets_labels"] = get_bool('astro', 'flag_planets_labels', 'true')

        result["preset_sky_time"] = get_float('navigation', 'preset_sky_time', 2451545.0)
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Count new screenshots ──────────────────────────────────────────────────
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
echo "New screenshots: $FINAL_SS_COUNT"

# ── 5. Check report file ───────────────────────────────────────────────────
REPORT_EXISTS="false"
REPORT_HAS_VENUS="false"
REPORT_HAS_DATE_LOC="false"
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_PATH" 2>/dev/null || echo "0")
    if grep -qi "Venus" "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_VENUS="true"
    fi
    if grep -qi "\(March\|2023\)" "$REPORT_PATH" 2>/dev/null && grep -qi "\(45\|40\)" "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_DATE_LOC="true"
    fi
fi

echo "Report: exists=$REPORT_EXISTS, has_venus=$REPORT_HAS_VENUS, context=$REPORT_HAS_DATE_LOC"

# ── 6. Write result JSON ──────────────────────────────────────────────────────
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "alt_m": config.get("alt_m"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_cardinal_points": config.get("flag_cardinal_points"),
    "flag_planets_labels": config.get("flag_planets_labels"),
    "preset_sky_time": config.get("preset_sky_time"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_size": $REPORT_SIZE,
    "report_has_venus": "$REPORT_HAS_VENUS" == "true",
    "report_has_date_loc": "$REPORT_HAS_DATE_LOC" == "true"
}

with open(f"/tmp/{result['task_name']}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "=== Export Complete ==="
cat /tmp/${TASK_NAME}_result.json