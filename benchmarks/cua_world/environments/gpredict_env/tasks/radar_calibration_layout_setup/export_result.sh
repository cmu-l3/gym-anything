#!/bin/bash
echo "=== Exporting radar_calibration_layout_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Check if Amateur.mod was deleted
AMATEUR_EXISTS="true"
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_EXISTS="false"
fi

# Search for Radar_Cal module
RADAR_CAL_EXISTS="false"
RADAR_CAL_SATELLITES=""
RADAR_CAL_SHOWMAP="1"
RADAR_CAL_SHOWPOLAR="1"
RADAR_CAL_MOD_NAME=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "radar"; then
        RADAR_CAL_EXISTS="true"
        RADAR_CAL_MOD_NAME="$modname"
        RADAR_CAL_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        
        # Check layout settings (SHOWMAP=0 and SHOWPOLARPLOT=0 means list only)
        map_val=$(grep -i "^SHOWMAP=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        if [ -n "$map_val" ]; then RADAR_CAL_SHOWMAP="$map_val"; fi
        
        polar_val=$(grep -i "^SHOWPOLARPLOT=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        if [ -n "$polar_val" ]; then RADAR_CAL_SHOWPOLAR="$polar_val"; fi
        
        break
    fi
done

# Search for Millstone Hill ground station
MILLSTONE_EXISTS="false"
MILLSTONE_LAT=""
MILLSTONE_LON=""
MILLSTONE_ALT=""
MILLSTONE_QTH_FILE=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth")
    
    # Check by name first
    if echo "$basename_qth" | grep -qi "millstone"; then
        MILLSTONE_EXISTS="true"
        MILLSTONE_QTH_FILE="$basename_qth"
    else
        # Fallback to checking coordinates (~42.6 Lat)
        lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lat_int=$(echo "$lat" | cut -d. -f1)
        if [ "$lat_int" = "42" ]; then
            MILLSTONE_EXISTS="true"
            MILLSTONE_QTH_FILE="$basename_qth"
        fi
    fi
    
    if [ "$MILLSTONE_EXISTS" = "true" ]; then
        MILLSTONE_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        MILLSTONE_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        MILLSTONE_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# Check global preferences (gpredict.cfg)
IMPERIAL_UNITS="false"
DEFAULT_QTH=""
GPREDICT_CFG_CONTENT=""

if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    UNIT_VAL=$(grep -i "^unit=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UNIT_VAL" = "1" ]; then
        IMPERIAL_UNITS="true"
    fi
    
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '\r')
    GPREDICT_CFG_CONTENT=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | tr '\n' '|' | sed 's/"/\\"/g')
fi

# Verify timestamps (anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_MODIFIED_TIME=$(stat -c %Y "${GPREDICT_CONF_DIR}/gpredict.cfg" 2>/dev/null || echo "0")

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "amateur_deleted": $([ "$AMATEUR_EXISTS" = "false" ] && echo "true" || echo "false"),
    "radar_cal_exists": $RADAR_CAL_EXISTS,
    "radar_cal_mod_name": "$(escape_json "$RADAR_CAL_MOD_NAME")",
    "radar_cal_satellites": "$(escape_json "$RADAR_CAL_SATELLITES")",
    "radar_cal_showmap": "$RADAR_CAL_SHOWMAP",
    "radar_cal_showpolar": "$RADAR_CAL_SHOWPOLAR",
    "millstone_exists": $MILLSTONE_EXISTS,
    "millstone_qth_file": "$(escape_json "$MILLSTONE_QTH_FILE")",
    "millstone_lat": "$(escape_json "$MILLSTONE_LAT")",
    "millstone_lon": "$(escape_json "$MILLSTONE_LON")",
    "millstone_alt": "$(escape_json "$MILLSTONE_ALT")",
    "imperial_units_enabled": $IMPERIAL_UNITS,
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "task_start_time": $TASK_START,
    "config_modified_time": $CONFIG_MODIFIED_TIME
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="