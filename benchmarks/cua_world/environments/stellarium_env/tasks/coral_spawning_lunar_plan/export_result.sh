#!/bin/bash
echo "=== Exporting coral_spawning_lunar_plan result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="coral_spawning_lunar_plan"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
DIVE_PLAN="/home/ga/Desktop/dive_plan.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot (while Stellarium is still running) ──────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to force config.ini save ───────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait for Stellarium to exit cleanly (config is saved on exit)
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited after ${i}s"
        break
    fi
    sleep 1
done

# Force kill if still running (config might not be fully saved, but we try)
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
    "flag_azimuthal_grid": None,
    "landscape_name": None,
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

        def get_str(section, key, default=''):
            try:
                return cfg.get(section, key)
            except:
                return default

        # Location (radians)
        result["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
        result["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)

        # Display flags
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')

        # Landscape name (check both init_location and location_run_once)
        ls_init = get_str('init_location', 'landscape_name', '')
        ls_run_once = get_str('location_run_once', 'landscape_name', '')
        result["landscape_name"] = ls_init if ls_init else ls_run_once

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

echo "Config parsed: $CONFIG_JSON"

# ── 4. Count new screenshots ─────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))
echo "Screenshots: initial=$INITIAL_SS_COUNT, current=$CURRENT_SS_COUNT, new=$NEW_SS_COUNT"

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi
echo "Screenshots newer than task start: $SS_NEW_BY_TIME"

if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi

# ── 5. Check dive plan file ───────────────────────────────────────────────
DIVE_PLAN_EXISTS="false"
HAS_LIZARD="false"
HAS_MOON="false"
HAS_CRUX="false"
DIVE_PLAN_SIZE=0

if [ -f "$DIVE_PLAN" ]; then
    DIVE_PLAN_EXISTS="true"
    DIVE_PLAN_SIZE=$(wc -c < "$DIVE_PLAN" 2>/dev/null || echo "0")

    if grep -qi "Lizard Island\|lizard island" "$DIVE_PLAN" 2>/dev/null; then
        HAS_LIZARD="true"
    fi

    if grep -qi "Moon\|moon" "$DIVE_PLAN" 2>/dev/null; then
        HAS_MOON="true"
    fi
    
    if grep -qi "Crux\|crux\|Southern Cross\|southern cross" "$DIVE_PLAN" 2>/dev/null; then
        HAS_CRUX="true"
    fi
fi

echo "Dive plan: exists=$DIVE_PLAN_EXISTS, lizard=$HAS_LIZARD, moon=$HAS_MOON, crux=$HAS_CRUX"

# ── 6. Write result JSON ──────────────────────────────────────────────────────
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "landscape_name": config.get("landscape_name"),
    "config_error": config.get("config_error"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "dive_plan_exists": $DIVE_PLAN_EXISTS,
    "dive_plan_size": $DIVE_PLAN_SIZE,
    "has_lizard": $HAS_LIZARD,
    "has_moon": $HAS_MOON,
    "has_crux": $HAS_CRUX
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true

echo "=== Export Complete ==="
cat "/tmp/${TASK_NAME}_result.json"