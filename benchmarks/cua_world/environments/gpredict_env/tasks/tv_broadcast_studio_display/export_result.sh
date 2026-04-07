#!/bin/bash
# Export script for tv_broadcast_studio_display task

echo "=== Exporting tv_broadcast_studio_display result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check Amateur.mod ---
AMATEUR_EXISTS="false"
if ls "${GPREDICT_MOD_DIR}"/Amateur*.mod 1> /dev/null 2>&1; then
    AMATEUR_EXISTS="true"
fi

# --- Check Studio_Map.mod ---
STUDIO_MAP_EXISTS="false"
STUDIO_MAP_NAME=""
SM_SATELLITES=""
SM_QTH=""
SM_NVIEWS="0"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "studio\|map"; then
        # Exclude Amateur if it matched somehow
        if echo "$modname" | grep -qi "amateur"; then continue; fi
        
        STUDIO_MAP_EXISTS="true"
        STUDIO_MAP_NAME="$modname"
        SM_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        SM_QTH=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        SM_NVIEWS=$(grep -i "^NVIEWS=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        break
    fi
done

# --- Check New York QTH ---
NY_EXISTS="false"
NY_QTH_FILENAME=""
NY_LAT=""
NY_LON=""
NY_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # Check by filename OR coordinates
    if echo "$basename_qth" | grep -qi "new\|york\|studio"; then
        MATCH="true"
    else
        lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]' | cut -d. -f1)
        if [ "$lat" = "40" ]; then
            MATCH="true"
        else
            MATCH="false"
        fi
    fi
    
    if [ "$MATCH" = "true" ]; then
        # Avoid matching Pittsburgh (Lat ~40.4)
        if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi
        
        NY_EXISTS="true"
        NY_QTH_FILENAME="$basename_qth"
        NY_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        NY_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        NY_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Check gpredict.cfg map preferences ---
GRID_VAL=""
SUN_VAL=""
MOON_VAL=""
SHADOW_VAL=""

CFG_FILE="${GPREDICT_CONF_DIR}/gpredict.cfg"
if [ -f "$CFG_FILE" ]; then
    # We want the values under [Map-View] specifically if possible, but global search is usually fine
    GRID_VAL=$(grep -i "^GRID=" "$CFG_FILE" | tail -1 | cut -d= -f2 | tr -d '[:space:]')
    SUN_VAL=$(grep -i "^SUN=" "$CFG_FILE" | tail -1 | cut -d= -f2 | tr -d '[:space:]')
    MOON_VAL=$(grep -i "^MOON=" "$CFG_FILE" | tail -1 | cut -d= -f2 | tr -d '[:space:]')
    SHADOW_VAL=$(grep -i "^SHADOW=" "$CFG_FILE" | tail -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# Escape JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/tv_broadcast_studio_display_result.json << EOF
{
    "amateur_exists": $AMATEUR_EXISTS,
    "studio_map_exists": $STUDIO_MAP_EXISTS,
    "studio_map_name": "$(escape_json "$STUDIO_MAP_NAME")",
    "sm_satellites": "$(escape_json "$SM_SATELLITES")",
    "sm_qth": "$(escape_json "$SM_QTH")",
    "sm_nviews": "$(escape_json "$SM_NVIEWS")",
    "ny_exists": $NY_EXISTS,
    "ny_qth_filename": "$(escape_json "$NY_QTH_FILENAME")",
    "ny_lat": "$(escape_json "$NY_LAT")",
    "ny_lon": "$(escape_json "$NY_LON")",
    "ny_alt": "$(escape_json "$NY_ALT")",
    "cfg_grid": "$(escape_json "$GRID_VAL")",
    "cfg_sun": "$(escape_json "$SUN_VAL")",
    "cfg_moon": "$(escape_json "$MOON_VAL")",
    "cfg_shadow": "$(escape_json "$SHADOW_VAL")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/tv_broadcast_studio_display_result.json"
cat /tmp/tv_broadcast_studio_display_result.json
echo ""
echo "=== Export Complete ==="