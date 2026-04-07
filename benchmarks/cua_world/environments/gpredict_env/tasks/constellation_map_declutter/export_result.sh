#!/bin/bash
echo "=== Exporting constellation_map_declutter result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot for VLM fallback verification
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Read Dense_Constellation.mod ---
MODULE_EXISTS="false"
MODULE_SATELLITES=""
MODULE_QTHFILE=""
MODULE_CONTENT=""

MOD_FILE="${GPREDICT_MOD_DIR}/Dense_Constellation.mod"
# If exact name not found, try case insensitive search
if [ ! -f "$MOD_FILE" ]; then
    for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
        [ -f "$mod" ] || continue
        modname=$(basename "$mod" .mod)
        if echo "$modname" | grep -qi "dense.*constellation"; then
            MOD_FILE="$mod"
            break
        fi
    done
fi

if [ -f "$MOD_FILE" ]; then
    MODULE_EXISTS="true"
    MODULE_SATELLITES=$(grep -i "^SATELLITES=" "$MOD_FILE" | head -1 | cut -d= -f2 | tr -d '\r\n')
    MODULE_QTHFILE=$(grep -i "^QTHFILE=" "$MOD_FILE" | head -1 | cut -d= -f2 | tr -d '\r\n')
    MODULE_CONTENT=$(cat "$MOD_FILE" | tr '\n' '|' | sed 's/"/\\"/g' | tr -d '\r')
fi

# --- Read SvalSat QTH ---
SVALSAT_EXISTS="false"
SVALSAT_LAT=""
SVALSAT_LON=""
SVALSAT_ALT=""
SVALSAT_FILENAME=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi
    
    # Check by name or coordinates (latitude ~78.2)
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    
    if echo "$basename_qth" | grep -qi "svalsat" || [ "$lat_int" = "78" ]; then
        SVALSAT_EXISTS="true"
        SVALSAT_FILENAME="$basename_qth.qth"
        SVALSAT_LAT="$lat"
        SVALSAT_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        SVALSAT_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Read gpredict.cfg ---
COORD_FORMAT=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Look for COORD_FORMAT value
    COORD_FORMAT=$(grep -i "^COORD_FORMAT=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/constellation_map_declutter_result.json << EOF
{
    "module_exists": $MODULE_EXISTS,
    "module_satellites": "$(escape_json "$MODULE_SATELLITES")",
    "module_qthfile": "$(escape_json "$MODULE_QTHFILE")",
    "module_content": "$(escape_json "$MODULE_CONTENT")",
    "svalsat_exists": $SVALSAT_EXISTS,
    "svalsat_filename": "$(escape_json "$SVALSAT_FILENAME")",
    "svalsat_lat": "$(escape_json "$SVALSAT_LAT")",
    "svalsat_lon": "$(escape_json "$SVALSAT_LON")",
    "svalsat_alt": "$(escape_json "$SVALSAT_ALT")",
    "coord_format": "$(escape_json "$COORD_FORMAT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/constellation_map_declutter_result.json"
cat /tmp/constellation_map_declutter_result.json
echo "=== Export Complete ==="