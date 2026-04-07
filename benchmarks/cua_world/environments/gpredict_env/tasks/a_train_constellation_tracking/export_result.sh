#!/bin/bash
# Export script for a_train_constellation_tracking task

echo "=== Exporting a_train_constellation_tracking result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check Amateur.mod ---
AMATEUR_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_EXISTS="true"
fi

# --- Check A_Train.mod ---
A_TRAIN_EXISTS="false"
A_TRAIN_SATELLITES=""
A_TRAIN_QTHFILE=""
A_TRAIN_MOD_PATH=""
A_TRAIN_HAS_AQUA="false"
A_TRAIN_HAS_AURA="false"
A_TRAIN_HAS_OCO2="false"
A_TRAIN_HAS_GCOM="false"

# Look for module named something like A_Train or ATrain
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "a.*train\|constellation"; then
        A_TRAIN_EXISTS="true"
        A_TRAIN_MOD_PATH="$mod"
        A_TRAIN_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        A_TRAIN_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        
        # Check specific satellites
        if echo "$A_TRAIN_SATELLITES" | grep -q "27424"; then A_TRAIN_HAS_AQUA="true"; fi
        if echo "$A_TRAIN_SATELLITES" | grep -q "28376"; then A_TRAIN_HAS_AURA="true"; fi
        if echo "$A_TRAIN_SATELLITES" | grep -q "40059"; then A_TRAIN_HAS_OCO2="true"; fi
        if echo "$A_TRAIN_SATELLITES" | grep -q "38337"; then A_TRAIN_HAS_GCOM="true"; fi
        break
    fi
done

# --- Check GSFC Goddard Ground Station ---
GSFC_EXISTS="false"
GSFC_LAT=""
GSFC_LON=""
GSFC_ALT=""
GSFC_FILENAME=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # Avoid Pittsburgh
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    
    # GSFC is ~38.99N
    if [ "$lat_int" = "38" ] || [ "$lat_int" = "39" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_abs=$(echo "$lon" | sed 's/-//')
        lon_int=$(echo "$lon_abs" | cut -d. -f1)
        
        # LON is ~76.85W
        if [ "$lon_int" = "76" ] || [ "$lon_int" = "77" ]; then
            GSFC_EXISTS="true"
            GSFC_FILENAME="$basename_qth.qth"
            GSFC_LAT="$lat"
            GSFC_LON="$lon"
            GSFC_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Capture Settings for Ground Track check ---
# Ground tracks can be enabled in gpredict.cfg or locally in the module config
CONFIG_DUMP=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    CONFIG_DUMP=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | grep -i "track" | tr '\n' '|' | sed 's/"/\\"/g')
fi

MOD_CONFIG_DUMP=""
if [ -n "$A_TRAIN_MOD_PATH" ] && [ -f "$A_TRAIN_MOD_PATH" ]; then
    MOD_CONFIG_DUMP=$(cat "$A_TRAIN_MOD_PATH" | tr '\n' '|' | sed 's/"/\\"/g')
fi

# Check if GPredict is currently running
APP_RUNNING=$(pgrep -f "gpredict" > /dev/null && echo "true" || echo "false")

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/a_train_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "amateur_exists": $AMATEUR_EXISTS,
    "a_train_exists": $A_TRAIN_EXISTS,
    "a_train_satellites": "$(escape_json "$A_TRAIN_SATELLITES")",
    "a_train_qthfile": "$(escape_json "$A_TRAIN_QTHFILE")",
    "a_train_has_aqua": $A_TRAIN_HAS_AQUA,
    "a_train_has_aura": $A_TRAIN_HAS_AURA,
    "a_train_has_oco2": $A_TRAIN_HAS_OCO2,
    "a_train_has_gcom": $A_TRAIN_HAS_GCOM,
    "gsfc_exists": $GSFC_EXISTS,
    "gsfc_filename": "$(escape_json "$GSFC_FILENAME")",
    "gsfc_lat": "$(escape_json "$GSFC_LAT")",
    "gsfc_lon": "$(escape_json "$GSFC_LON")",
    "gsfc_alt": "$(escape_json "$GSFC_ALT")",
    "global_track_settings": "$(escape_json "$CONFIG_DUMP")",
    "mod_track_settings": "$(escape_json "$MOD_CONFIG_DUMP")"
}
EOF

echo "Result saved to /tmp/a_train_result.json"
cat /tmp/a_train_result.json
echo ""
echo "=== Export Complete ==="