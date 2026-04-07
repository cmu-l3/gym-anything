#!/bin/bash
# Export script for geo_vsat_alignment_setup task

echo "=== Exporting geo_vsat_alignment_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
GPREDICT_TRSP_DIR="${GPREDICT_CONF_DIR}/trsp"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

# --- Read Omaha_DataCenter.qth ---
OMAHA_QTH="${GPREDICT_CONF_DIR}/Omaha_DataCenter.qth"
OMAHA_EXISTS="false"
OMAHA_LAT=""
OMAHA_LON=""
OMAHA_ALT=""
OMAHA_WX=""

# Search case-insensitively for Omaha qth file
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    if echo "$qth" | grep -qi "omaha"; then
        OMAHA_QTH="$qth"
        OMAHA_EXISTS="true"
        OMAHA_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        OMAHA_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        OMAHA_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        OMAHA_WX=$(grep -i "^WX=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Read GEO_Alignment.mod ---
GEO_MOD_EXISTS="false"
GEO_SATELLITES=""
GEO_QTHFILE=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    if echo "$mod" | grep -qi "geo.*align"; then
        GEO_MOD_EXISTS="true"
        GEO_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        GEO_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2)
        break
    fi
done

# --- Read Transponder files ---
TRSP_43013_EXISTS="false"
TRSP_43013_CONTENT=""
if [ -f "${GPREDICT_TRSP_DIR}/43013.trsp" ]; then
    TRSP_43013_EXISTS="true"
    TRSP_43013_CONTENT=$(cat "${GPREDICT_TRSP_DIR}/43013.trsp" | tr '\n' '|' | sed 's/"/\\"/g')
fi

TRSP_51850_EXISTS="false"
TRSP_51850_CONTENT=""
if [ -f "${GPREDICT_TRSP_DIR}/51850.trsp" ]; then
    TRSP_51850_EXISTS="true"
    TRSP_51850_CONTENT=$(cat "${GPREDICT_TRSP_DIR}/51850.trsp" | tr '\n' '|' | sed 's/"/\\"/g')
fi

TRSP_36516_EXISTS="false"
TRSP_36516_CONTENT=""
if [ -f "${GPREDICT_TRSP_DIR}/36516.trsp" ]; then
    TRSP_36516_EXISTS="true"
    TRSP_36516_CONTENT=$(cat "${GPREDICT_TRSP_DIR}/36516.trsp" | tr '\n' '|' | sed 's/"/\\"/g')
fi

# --- Check UTC time setting in gpredict.cfg ---
UTC_TIME_ENABLED="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
GPREDICT_CFG_CONTENT=""

if [ -f "$GPREDICT_CFG" ]; then
    UTC_VAL=$(grep -i "^utc=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UTC_VAL" = "1" ]; then
        UTC_TIME_ENABLED="true"
    fi
    GPREDICT_CFG_CONTENT=$(cat "$GPREDICT_CFG" | tr '\n' '|' | sed 's/"/\\"/g')
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/geo_vsat_alignment_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omaha_exists": $OMAHA_EXISTS,
    "omaha_lat": "$(escape_json "$OMAHA_LAT")",
    "omaha_lon": "$(escape_json "$OMAHA_LON")",
    "omaha_alt": "$(escape_json "$OMAHA_ALT")",
    "omaha_wx": "$(escape_json "$OMAHA_WX")",
    "geo_mod_exists": $GEO_MOD_EXISTS,
    "geo_satellites": "$(escape_json "$GEO_SATELLITES")",
    "geo_qthfile": "$(escape_json "$GEO_QTHFILE")",
    "trsp_43013_exists": $TRSP_43013_EXISTS,
    "trsp_43013_content": "$TRSP_43013_CONTENT",
    "trsp_51850_exists": $TRSP_51850_EXISTS,
    "trsp_51850_content": "$TRSP_51850_CONTENT",
    "trsp_36516_exists": $TRSP_36516_EXISTS,
    "trsp_36516_content": "$TRSP_36516_CONTENT",
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "Result saved to /tmp/geo_vsat_alignment_result.json"
cat /tmp/geo_vsat_alignment_result.json
echo ""
echo "=== Export Complete ==="