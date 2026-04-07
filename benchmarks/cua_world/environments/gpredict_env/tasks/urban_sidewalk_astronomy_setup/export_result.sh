#!/bin/bash
# Export script for urban_sidewalk_astronomy_setup task

echo "=== Exporting urban_sidewalk_astronomy_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Parse Global Predict Constraints from gpredict.cfg ---
PREDICT_MIN_EL=""
PREDICT_MAX_SUN_EL=""
PREDICT_NUM_PASSES=""
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    PREDICT_MIN_EL=$(grep -i "^MIN_EL=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    PREDICT_MAX_SUN_EL=$(grep -i "^MAX_SUN_EL=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    PREDICT_NUM_PASSES=$(grep -i "^NUM_PASSES=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# --- Check Chicago_Urban ground station ---
CHICAGO_URBAN_EXISTS="false"
CHICAGO_URBAN_LAT=""
CHICAGO_URBAN_LON=""
CHICAGO_URBAN_ALT=""
CHICAGO_QTH_FILE=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    # Search by name explicitly or by coordinates if renamed
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    
    if echo "$basename_qth" | grep -qi "chicago" || [ "$lat_int" = "41" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | sed 's/-//' | cut -d. -f1)
        if [ "$lon_int" = "87" ]; then
            CHICAGO_URBAN_EXISTS="true"
            CHICAGO_QTH_FILE="$basename_qth.qth"
            CHICAGO_URBAN_LAT="$lat"
            CHICAGO_URBAN_LON="$lon"
            CHICAGO_URBAN_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Check Urban_Bright module ---
URBAN_BRIGHT_EXISTS="false"
URBAN_BRIGHT_SATELLITES=""
URBAN_BRIGHT_QTHFILE=""
UB_HAS_ISS="false"
UB_HAS_CSS="false"
UB_MTIME="0"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "urban\|bright"; then
        URBAN_BRIGHT_EXISTS="true"
        URBAN_BRIGHT_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        URBAN_BRIGHT_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        
        if echo "$URBAN_BRIGHT_SATELLITES" | grep -q "25544"; then UB_HAS_ISS="true"; fi
        if echo "$URBAN_BRIGHT_SATELLITES" | grep -q "48274"; then UB_HAS_CSS="true"; fi
        
        UB_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        break
    fi
done

# --- Check if Amateur module was deleted ---
AMATEUR_DELETED="true"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_DELETED="false"
fi

TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/urban_sidewalk_astronomy_result.json << EOF
{
    "task_start_time": $TASK_START_TIME,
    "predict_min_el": "$(escape_json "$PREDICT_MIN_EL")",
    "predict_max_sun_el": "$(escape_json "$PREDICT_MAX_SUN_EL")",
    "predict_num_passes": "$(escape_json "$PREDICT_NUM_PASSES")",
    "chicago_urban_exists": $CHICAGO_URBAN_EXISTS,
    "chicago_urban_lat": "$(escape_json "$CHICAGO_URBAN_LAT")",
    "chicago_urban_lon": "$(escape_json "$CHICAGO_URBAN_LON")",
    "chicago_urban_alt": "$(escape_json "$CHICAGO_URBAN_ALT")",
    "chicago_qth_file": "$(escape_json "$CHICAGO_QTH_FILE")",
    "urban_bright_exists": $URBAN_BRIGHT_EXISTS,
    "urban_bright_mtime": $UB_MTIME,
    "urban_bright_satellites": "$(escape_json "$URBAN_BRIGHT_SATELLITES")",
    "urban_bright_qthfile": "$(escape_json "$URBAN_BRIGHT_QTHFILE")",
    "ub_has_iss": $UB_HAS_ISS,
    "ub_has_css": $UB_HAS_CSS,
    "amateur_deleted": $AMATEUR_DELETED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/urban_sidewalk_astronomy_result.json"
cat /tmp/urban_sidewalk_astronomy_result.json
echo ""
echo "=== Export Complete ==="