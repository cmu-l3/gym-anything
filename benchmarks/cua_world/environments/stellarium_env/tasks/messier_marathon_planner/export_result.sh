#!/bin/bash
echo "=== Exporting messier_marathon_planner result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="messier_marathon_planner"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
PLAN_PATH="/home/ga/Desktop/marathon_plan.txt"

# 1. Final screenshot
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Terminate Stellarium safely to save config.ini
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

# 3. Parse config.ini
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None, "alt_m": None,
    "flag_atmosphere": None, "flag_landscape": None,
    "flag_azimuthal_grid": None, "flag_nebula": None,
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
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        
        # Nebulae flag might be stored in [astro] or [viewing] based on Stellarium version
        flag_nebula = get_bool('astro', 'flag_nebula', 'false')
        if not flag_nebula:
            flag_nebula = get_bool('viewing', 'flag_nebula', 'false')
        result["flag_nebula"] = flag_nebula
        
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Count newly generated screenshots (checking both count diff and mtime)
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
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

# 5. Verify the marathon plan file contents
PLAN_EXISTS="false"
PLAN_HAS_M74="false"
PLAN_HAS_M30="false"
PLAN_HAS_KITT="false"

if [ -f "$PLAN_PATH" ]; then
    PLAN_EXISTS="true"
    if grep -qi "M74" "$PLAN_PATH" 2>/dev/null; then
        PLAN_HAS_M74="true"
    fi
    if grep -qi "M30" "$PLAN_PATH" 2>/dev/null; then
        PLAN_HAS_M30="true"
    fi
    if grep -qi "Kitt" "$PLAN_PATH" 2>/dev/null; then
        PLAN_HAS_KITT="true"
    fi
fi

# 6. Save JSON result output
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task_start": $TASK_START,
    "config_info": $CONFIG_JSON,
    "new_screenshot_count": $FINAL_SS_COUNT,
    "plan_exists": $PLAN_EXISTS,
    "plan_has_m74": $PLAN_HAS_M74,
    "plan_has_m30": $PLAN_HAS_M30,
    "plan_has_kitt": $PLAN_HAS_KITT
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "=== Export Complete ==="