#!/bin/bash
echo "=== Exporting celestial_nav_training result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="celestial_nav_training"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NAV_LOG="/home/ga/Desktop/nav_log.txt"

# ── 1. Take final screenshot ──────────────────────────────────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium ───────────────────────────────────────
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
    "flag_equatorial_grid": None, "flag_azimuthal_grid": None,
    "flag_constellation_drawing": None, "flag_constellation_art": None,
    "flag_star_name": None,
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
        result["flag_equatorial_grid"] = get_bool('viewing', 'flag_equatorial_grid', 'false')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_constellation_art"] = get_bool('viewing', 'flag_constellation_art', 'false')
        result["flag_star_name"] = get_bool('stars', 'flag_star_name', 'true')
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

# ── 5. Check navigation log ───────────────────────────────────────────────────
NAV_LOG_EXISTS="false"
NAV_LOG_HAS_POLARIS="false"
NAV_LOG_HAS_SIRIUS="false"
NAV_LOG_HAS_CANOPUS="false"
NAV_LOG_HAS_VEGA="false"
NAV_LOG_SIZE=0

if [ -f "$NAV_LOG" ]; then
    NAV_LOG_EXISTS="true"
    NAV_LOG_SIZE=$(wc -c < "$NAV_LOG" 2>/dev/null || echo "0")
    grep -qi "Polaris\|polaris\|north star\|alpha ursae" "$NAV_LOG" 2>/dev/null && NAV_LOG_HAS_POLARIS="true"
    grep -qi "Sirius\|sirius\|dog star\|alpha canis" "$NAV_LOG" 2>/dev/null && NAV_LOG_HAS_SIRIUS="true"
    grep -qi "Canopus\|canopus\|alpha carinae" "$NAV_LOG" 2>/dev/null && NAV_LOG_HAS_CANOPUS="true"
    grep -qi "Vega\|vega\|alpha lyrae" "$NAV_LOG" 2>/dev/null && NAV_LOG_HAS_VEGA="true"
fi

echo "Nav log: exists=$NAV_LOG_EXISTS, polaris=$NAV_LOG_HAS_POLARIS, sirius=$NAV_LOG_HAS_SIRIUS, canopus=$NAV_LOG_HAS_CANOPUS, vega=$NAV_LOG_HAS_VEGA"

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
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "flag_constellation_art": config.get("flag_constellation_art"),
    "flag_star_name": config.get("flag_star_name"),
    "preset_sky_time": config.get("preset_sky_time"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "nav_log_exists": $NAV_LOG_EXISTS,
    "nav_log_has_polaris": $NAV_LOG_HAS_POLARIS,
    "nav_log_has_sirius": $NAV_LOG_HAS_SIRIUS,
    "nav_log_has_canopus": $NAV_LOG_HAS_CANOPUS,
    "nav_log_has_vega": $NAV_LOG_HAS_VEGA,
    "nav_log_size": $NAV_LOG_SIZE,
    "config_error": config.get("config_error")
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written")
PYEOF

echo "=== Export Complete ==="
cat /tmp/${TASK_NAME}_result.json
