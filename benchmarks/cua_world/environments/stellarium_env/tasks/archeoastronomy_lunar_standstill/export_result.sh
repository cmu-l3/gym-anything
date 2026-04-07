#!/bin/bash
echo "=== Exporting archeoastronomy_lunar_standstill result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="archeoastronomy_lunar_standstill"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
BRIEF_NOTES="/home/ga/Desktop/standstill_brief.txt"
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
    "flag_azimuthal_grid": None, "flag_cardinal_points": None,
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
        result["alt_m"] = get_float('location_run_once', 'altitude', 0.0)
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_cardinal_points"] = get_bool('landscape', 'flag_cardinal_points', 'false')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
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

# ── 5. Check brief notes file ─────────────────────────────────────────────────
BRIEF_EXISTS="false"
BRIEF_HAS_CHIMNEY_ROCK="false"
BRIEF_HAS_DATE="false"
BRIEF_HAS_AZIMUTH="false"
BRIEF_SIZE=0

if [ -f "$BRIEF_NOTES" ]; then
    BRIEF_EXISTS="true"
    BRIEF_SIZE=$(wc -c < "$BRIEF_NOTES" 2>/dev/null || echo "0")
    if grep -qi "chimney" "$BRIEF_NOTES" 2>/dev/null; then
        BRIEF_HAS_CHIMNEY_ROCK="true"
    fi
    if grep -q "2024" "$BRIEF_NOTES" 2>/dev/null && grep -qi "dec" "$BRIEF_NOTES" 2>/dev/null; then
        BRIEF_HAS_DATE="true"
    fi
    if grep -qE "52|53|54" "$BRIEF_NOTES" 2>/dev/null; then
        BRIEF_HAS_AZIMUTH="true"
    fi
fi

echo "Brief notes: exists=$BRIEF_EXISTS, chimney_rock=$BRIEF_HAS_CHIMNEY_ROCK, date=$BRIEF_HAS_DATE, azimuth=$BRIEF_HAS_AZIMUTH"

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
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "flag_cardinal_points": config.get("flag_cardinal_points"),
    "config_error": config.get("config_error"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "brief_exists": $BRIEF_EXISTS,
    "brief_has_chimney_rock": $BRIEF_HAS_CHIMNEY_ROCK,
    "brief_has_date": $BRIEF_HAS_DATE,
    "brief_has_azimuth": $BRIEF_HAS_AZIMUTH,
    "brief_size": $BRIEF_SIZE
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/${TASK_NAME}_result.json