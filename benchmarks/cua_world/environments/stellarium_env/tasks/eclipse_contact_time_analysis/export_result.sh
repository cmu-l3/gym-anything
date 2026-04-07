#!/bin/bash
echo "=== Exporting eclipse_contact_time_analysis result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="eclipse_contact_time_analysis"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
REPORT_PATH="/home/ga/Desktop/eclipse_contact_times.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot while Stellarium is still running ────────────────
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
    "last_location": None,
    "lat_rad": None,
    "lon_rad": None,
    "alt_m": None,
    "flag_atmosphere": None,
    "flag_landscape": None,
    "flag_constellation_drawing": None,
    "flag_constellation_name": None,
    "flag_equatorial_grid": None,
    "flag_azimuthal_grid": None,
    "flag_star_name": None,
    "preset_sky_time": None,
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

        # Location — try both Stellarium config formats
        # v0.20.4 uses [init_location] with last_location (text name)
        # Some versions use [location_run_once] with lat/lon in radians
        try:
            result["last_location"] = cfg.get('init_location', 'last_location').strip()
        except:
            pass
        result["lat_rad"] = get_float('location_run_once', 'latitude')
        result["lon_rad"] = get_float('location_run_once', 'longitude')
        result["alt_m"] = get_float('location_run_once', 'altitude')

        # Display flags
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_constellation_name"] = get_bool('viewing', 'flag_constellation_name', 'false')
        result["flag_equatorial_grid"] = get_bool('viewing', 'flag_equatorial_grid', 'false')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_star_name"] = get_bool('stars', 'flag_star_name', 'true')

        # Navigation time
        result["preset_sky_time"] = get_float('navigation', 'preset_sky_time')

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

echo "Config parsed: $CONFIG_JSON"

# ── 4. Count new screenshots ─────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))

# Also count screenshots newer than task start
SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi
echo "Screenshots: initial=$INITIAL_SS_COUNT, current=$CURRENT_SS_COUNT, new=$NEW_SS_COUNT, by_time=$SS_NEW_BY_TIME"

# Use the higher of the two counts
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi

# ── 5. Check report file existence and content ───────────────────────────────
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_C1="false"
REPORT_HAS_C2="false"
REPORT_HAS_C3="false"
REPORT_HAS_C4="false"
REPORT_HAS_ALTITUDE="false"
REPORT_HAS_TOTALITY="false"
REPORT_HAS_VISIBLE_OBJECTS="false"
REPORT_HAS_ROME="false"
REPORT_HAS_REYKJAVIK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_CONTENT=$(cat "$REPORT_PATH" 2>/dev/null || echo "")

    # Check for contact time mentions
    if echo "$REPORT_CONTENT" | grep -qiE "C1|first contact|partial.*begin"; then
        REPORT_HAS_C1="true"
    fi
    if echo "$REPORT_CONTENT" | grep -qiE "C2|second contact|totality.*begin"; then
        REPORT_HAS_C2="true"
    fi
    if echo "$REPORT_CONTENT" | grep -qiE "C3|third contact|totality.*end"; then
        REPORT_HAS_C3="true"
    fi
    if echo "$REPORT_CONTENT" | grep -qiE "C4|fourth contact|partial.*end"; then
        REPORT_HAS_C4="true"
    fi

    # Check for altitude/azimuth data
    if echo "$REPORT_CONTENT" | grep -qiE "altitude|alt[^a-z]|elevation|azimuth|az[^a-z]"; then
        REPORT_HAS_ALTITUDE="true"
    fi

    # Check for totality duration mention
    if echo "$REPORT_CONTENT" | grep -qiE "duration|totality.*sec|totality.*min|C3.*minus.*C2|C3.*C2"; then
        REPORT_HAS_TOTALITY="true"
    fi

    # Check for visible objects during totality
    if echo "$REPORT_CONTENT" | grep -qiE "visible|planet|star|mercury|venus|mars|jupiter|saturn|bright.*object"; then
        REPORT_HAS_VISIBLE_OBJECTS="true"
    fi

    # Check for Rome control observation
    if echo "$REPORT_CONTENT" | grep -qiE "rome|control|partial.*eclipse|not.*total"; then
        REPORT_HAS_ROME="true"
    fi

    # Check for primary location mention
    if echo "$REPORT_CONTENT" | grep -qiE "reykjavik|iceland"; then
        REPORT_HAS_REYKJAVIK="true"
    fi
fi

echo "Report: exists=$REPORT_EXISTS, size=$REPORT_SIZE bytes"
echo "Report content checks: C1=$REPORT_HAS_C1, C2=$REPORT_HAS_C2, C3=$REPORT_HAS_C3, C4=$REPORT_HAS_C4"
echo "Report: altitude=$REPORT_HAS_ALTITUDE, totality=$REPORT_HAS_TOTALITY, objects=$REPORT_HAS_VISIBLE_OBJECTS"
echo "Report: rome=$REPORT_HAS_ROME, reykjavik=$REPORT_HAS_REYKJAVIK"

# ── 6. Write result JSON ─────────────────────────────────────────────────────
python3 << PYEOF
import json, os

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "last_location": config.get("last_location"),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "alt_m": config.get("alt_m"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "flag_constellation_name": config.get("flag_constellation_name"),
    "flag_equatorial_grid": config.get("flag_equatorial_grid"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "preset_sky_time": config.get("preset_sky_time"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_size_bytes": $REPORT_SIZE,
    "report_has_c1": "$REPORT_HAS_C1" == "true",
    "report_has_c2": "$REPORT_HAS_C2" == "true",
    "report_has_c3": "$REPORT_HAS_C3" == "true",
    "report_has_c4": "$REPORT_HAS_C4" == "true",
    "report_has_altitude": "$REPORT_HAS_ALTITUDE" == "true",
    "report_has_totality": "$REPORT_HAS_TOTALITY" == "true",
    "report_has_visible_objects": "$REPORT_HAS_VISIBLE_OBJECTS" == "true",
    "report_has_rome": "$REPORT_HAS_ROME" == "true",
    "report_has_reykjavik": "$REPORT_HAS_REYKJAVIK" == "true",
    "config_error": config.get("config_error")
}

output_path = "/tmp/${TASK_NAME}_result.json"
with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

os.chmod(output_path, 0o666)
print("Result written to " + output_path)
PYEOF

echo "=== Export Complete ==="
cat /tmp/${TASK_NAME}_result.json
