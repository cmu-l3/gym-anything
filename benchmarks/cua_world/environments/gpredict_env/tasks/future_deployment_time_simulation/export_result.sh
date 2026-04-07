#!/bin/bash
# Export script for future_deployment_time_simulation task

echo "=== Exporting future_deployment_time_simulation result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot (CRITICAL for Time Controller VLM verification)
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check Austin_TX QTH (scan by lat ~30.2, lon ~-97.7) ---
AUSTIN_EXISTS="false"
AUSTIN_QTH_FILE=""
AUSTIN_LAT=""
AUSTIN_LON=""
AUSTIN_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "30" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_abs=$(echo "$lon" | sed 's/-//')
        lon_int=$(echo "$lon_abs" | cut -d. -f1)
        if [ "$lon_int" = "97" ]; then
            AUSTIN_EXISTS="true"
            AUSTIN_QTH_FILE="$basename_qth.qth"
            AUSTIN_LAT="$lat"
            AUSTIN_LON="$lon"
            AUSTIN_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Check Deployment_Sim.mod ---
MODULE_EXISTS="false"
MODULE_SATELLITES=""
MODULE_HAS_ISS="false"   # 25544
MODULE_HAS_CSS="false"   # 48274

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "deploy\|sim"; then
        MODULE_EXISTS="true"
        MODULE_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        if echo "$MODULE_SATELLITES" | grep -q "25544"; then MODULE_HAS_ISS="true"; fi
        if echo "$MODULE_SATELLITES" | grep -q "48274"; then MODULE_HAS_CSS="true"; fi
        break
    fi
done

# --- Check gpredict.cfg for UTC and Default QTH ---
UTC_ENABLED="false"
DEFAULT_QTH_IS_AUSTIN="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    UTC_VAL=$(grep -i "^utc=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UTC_VAL" = "1" ]; then
        UTC_ENABLED="true"
    fi

    # Check if the configured default QTH matches the Austin QTH file we found
    CONF_DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$AUSTIN_EXISTS" = "true" ] && [ "$CONF_DEFAULT_QTH" = "$AUSTIN_QTH_FILE" ]; then
        DEFAULT_QTH_IS_AUSTIN="true"
    elif echo "$CONF_DEFAULT_QTH" | grep -qi "austin"; then
        # Fallback if names just match textually
        DEFAULT_QTH_IS_AUSTIN="true"
    fi
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/future_deployment_time_simulation_result.json << EOF
{
    "austin_exists": $AUSTIN_EXISTS,
    "austin_qth_file": "$(escape_json "$AUSTIN_QTH_FILE")",
    "austin_lat": "$(escape_json "$AUSTIN_LAT")",
    "austin_lon": "$(escape_json "$AUSTIN_LON")",
    "austin_alt": "$(escape_json "$AUSTIN_ALT")",
    "module_exists": $MODULE_EXISTS,
    "module_satellites": "$(escape_json "$MODULE_SATELLITES")",
    "module_has_iss": $MODULE_HAS_ISS,
    "module_has_css": $MODULE_HAS_CSS,
    "utc_enabled": $UTC_ENABLED,
    "default_qth_is_austin": $DEFAULT_QTH_IS_AUSTIN,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/future_deployment_time_simulation_result.json"
cat /tmp/future_deployment_time_simulation_result.json
echo ""
echo "=== Export Complete ==="