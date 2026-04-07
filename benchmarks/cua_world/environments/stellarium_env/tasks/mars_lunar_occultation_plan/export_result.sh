#!/bin/bash
echo "=== Exporting mars_lunar_occultation_plan result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="mars_lunar_occultation_plan"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
PLAN_NOTES="/home/ga/Desktop/occultation_plan.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot (while Stellarium is still running) ──────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to force config.ini save ───────────────
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

# ── 3. Parse config.ini with Python ──────────────────────────────────────────
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None,
    "lon_rad": None,
    "alt_m": None,
    "flag_atmosphere": None,
    "flag_landscape": None,
    "flag_equatorial_grid": None,
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
        result["alt_m"] = get_float('location_run_once', 'altitude', 0.0)

        # Display flags
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_equatorial_grid"] = get_bool('viewing', 'flag_equatorial_grid', 'false')

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Count new screenshots ─────────────────────────────────────────────────
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

# ── 5. Check observation plan file ───────────────────────────────────────────────
PLAN_EXISTS="false"
PLAN_HAS_GRIFFITH="false"
PLAN_HAS_0230="false"
PLAN_HAS_0330="false"

if [ -f "$PLAN_NOTES" ]; then
    PLAN_EXISTS="true"
    if grep -qi "Griffith" "$PLAN_NOTES" 2>/dev/null; then
        PLAN_HAS_GRIFFITH="true"
    fi
    if grep -q "02:30\|2:30" "$PLAN_NOTES" 2>/dev/null; then
        PLAN_HAS_0230="true"
    fi
    if grep -q "03:30\|3:30" "$PLAN_NOTES" 2>/dev/null; then
        PLAN_HAS_0330="true"
    fi
fi

# ── 6. Combine and export result JSON ────────────────────────────────────────
python3 << PYEOF
import json
import os

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
    "flag_equatorial_grid": config.get("flag_equatorial_grid"),
    "config_error": config.get("config_error"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "plan_exists": "$PLAN_EXISTS" == "true",
    "plan_has_griffith": "$PLAN_HAS_GRIFFITH" == "true",
    "plan_has_0230": "$PLAN_HAS_0230" == "true",
    "plan_has_0330": "$PLAN_HAS_0330" == "true"
}

out_path = "/tmp/${TASK_NAME}_result.json"
with open(out_path, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(out_path, 0o666)
PYEOF

echo "Result saved to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json
echo "=== Export Complete ==="