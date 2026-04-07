#!/bin/bash
echo "=== Exporting everest_summit_planning result ==="

TASK_NAME="everest_summit_planning"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_ss_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
BRIEFING_NOTES="/home/ga/Desktop/summit_briefing.txt"

# ── 1. Take final screenshot before killing ───────────────────────────────────
DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# ── 2. Terminate Stellarium gracefully to flush config ────────────────────────
echo "Terminating Stellarium..."
pkill -SIGTERM stellarium 2>/dev/null || true
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
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
    "flag_constellation_drawing": None, "flag_constellation_labels": None,
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
        result["alt_m"] = get_float('location_run_once', 'altitude')
        
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_cardinal_points"] = get_bool('landscape', 'flag_cardinal_points', 'false')
        
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_constellation_labels"] = get_bool('viewing', 'flag_constellation_names', 'false')
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Analyze Screenshots ────────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))
SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi

FINAL_SS_COUNT=$NEW_SS_COUNT
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
fi

# ── 5. Analyze Briefing Notes ─────────────────────────────────────────────────
BRIEFING_EXISTS="false"
HAS_EVEREST="false"
HAS_FULL_MOON="false"
HAS_SUNRISE_TIME="false"

if [ -f "$BRIEFING_NOTES" ]; then
    BRIEFING_EXISTS="true"
    if grep -qi "Everest" "$BRIEFING_NOTES"; then HAS_EVEREST="true"; fi
    if grep -qi "Full" "$BRIEFING_NOTES"; then HAS_FULL_MOON="true"; fi
    if grep -qi "23:\|sunrise" "$BRIEFING_NOTES"; then HAS_SUNRISE_TIME="true"; fi
fi

# ── 6. Write Result JSON ──────────────────────────────────────────────────────
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "alt_m": config.get("alt_m"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "flag_cardinal_points": config.get("flag_cardinal_points"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "briefing_exists": $BRIEFING_EXISTS,
    "briefing_has_everest": $HAS_EVEREST,
    "briefing_has_full_moon": $HAS_FULL_MOON,
    "briefing_has_sunrise_time": $HAS_SUNRISE_TIME
}

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json
echo "=== Export Complete ==="