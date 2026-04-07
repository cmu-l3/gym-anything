#!/bin/bash
echo "=== Exporting midnight_sun_educational_sequence result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="midnight_sun_educational_sequence"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
LESSON_PLAN="/home/ga/Desktop/arctic_lesson_plan.txt"

# ── 1. Take final screenshot (while Stellarium is still running) ──────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to force config.ini save ───────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait for Stellarium to exit cleanly
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited after ${i}s"
        break
    fi
    sleep 1
done

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
    "flag_atmosphere": None,
    "flag_landscape": None,
    "flag_azimuthal_grid": None,
    "flag_cardinal_points": None,
    "config_error": None
}

if os.path.exists(config_path):
    result["config_exists"] = True
    try:
        cfg = configparser.RawConfigParser()
        cfg.read(config_path)

        def get_bool(section, key, default='false'):
            try:
                # Check different sections since Stellarium versions vary
                if cfg.has_option(section, key):
                    return cfg.get(section, key).lower().strip() == 'true'
                # Fallback to checking other common sections
                for sec in ['landscape', 'viewing', 'gui', 'main']:
                    if cfg.has_option(sec, key):
                        return cfg.get(sec, key).lower().strip() == 'true'
                return default.lower() == 'true'
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
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_cardinal_points"] = get_bool('landscape', 'flag_cardinal_points', 'false')

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Count new screenshots ─────────────────────────────────────────────────
SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f -name "*.png" 2>/dev/null | wc -l)
fi

# ── 5. Check lesson plan file ───────────────────────────────────────────────
LESSON_PLAN_EXISTS="false"
LESSON_PLAN_SIZE=0
HAS_LONGYEARBYEN="false"
HAS_WINTER_DEC="false"
HAS_SUMMER_JUN="false"
HAS_HORIZON_OBS="false"

if [ -f "$LESSON_PLAN" ]; then
    LESSON_PLAN_EXISTS="true"
    LESSON_PLAN_SIZE=$(wc -c < "$LESSON_PLAN" 2>/dev/null || echo "0")
    
    # Read lowercased content for flexible keyword matching
    CONTENT=$(cat "$LESSON_PLAN" | tr '[:upper:]' '[:lower:]')
    
    if echo "$CONTENT" | grep -q "longyearbyen\|svalbard"; then
        HAS_LONGYEARBYEN="true"
    fi
    if echo "$CONTENT" | grep -q "december\|winter\|dec 21"; then
        HAS_WINTER_DEC="true"
    fi
    if echo "$CONTENT" | grep -q "june\|summer\|jun 21"; then
        HAS_SUMMER_JUN="true"
    fi
    if echo "$CONTENT" | grep -q "horizon\|above\|below\|visible\|continuous\|dark\|daylight"; then
        HAS_HORIZON_OBS="true"
    fi
fi

# ── 6. Write result JSON ────────────────────────────────────────────────────
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "flag_cardinal_points": config.get("flag_cardinal_points"),
    "new_screenshot_count": $SS_NEW_BY_TIME,
    "lesson_plan_exists": $LESSON_PLAN_EXISTS,
    "lesson_plan_size": $LESSON_PLAN_SIZE,
    "has_longyearbyen": $HAS_LONGYEARBYEN,
    "has_winter_dec": $HAS_WINTER_DEC,
    "has_summer_jun": $HAS_SUMMER_JUN,
    "has_horizon_obs": $HAS_HORIZON_OBS
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "Result saved to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json
echo "=== Export complete ==="