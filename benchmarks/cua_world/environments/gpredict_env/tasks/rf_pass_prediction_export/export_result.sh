#!/bin/bash
# Export script for rf_pass_prediction_export task

echo "=== Exporting rf_pass_prediction_export result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Read Dallas_Field.qth ---
DALLAS_EXISTS="false"
DALLAS_LAT=""
DALLAS_LON=""
DALLAS_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # We look for Dallas_Field or coordinates matching the requirement
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "32" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_abs=$(echo "$lon" | sed 's/-//')
        lon_int=$(echo "$lon_abs" | cut -d. -f1)
        if [ "$lon_int" = "96" ]; then
            DALLAS_EXISTS="true"
            DALLAS_LAT="$lat"
            DALLAS_LON="$lon"
            DALLAS_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Read Field_Testing.mod ---
FIELD_MOD_EXISTS="false"
FIELD_SATELLITES=""
FIELD_LAYOUT="unknown"
FIELD_QTHFILE=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "field\|test"; then
        FIELD_MOD_EXISTS="true"
        FIELD_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        FIELD_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2)
        
        # Check Layout. LIST ONLY usually has SHOWMAP=0 and SHOWPOLARPLOT=0
        SHOWMAP=$(grep -i "^SHOWMAP=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        SHOWPOLARPLOT=$(grep -i "^SHOWPOLARPLOT=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        break
    fi
done

# --- Check Exported Text Files ---
FO29_EXISTS="false"
FO29_CREATED_DURING="false"
FO29_CONTENT=""

if [ -f "/home/ga/Documents/FO29_passes.txt" ]; then
    FO29_EXISTS="true"
    MTIME=$(stat -c %Y "/home/ga/Documents/FO29_passes.txt" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        FO29_CREATED_DURING="true"
    fi
    # Grab the top part of the file to verify format and presence of satellite passes
    FO29_CONTENT=$(head -n 20 "/home/ga/Documents/FO29_passes.txt" | tr '\n' '|' | tr -d '\r' | sed 's/"/\\"/g')
fi

RS44_EXISTS="false"
RS44_CREATED_DURING="false"
RS44_CONTENT=""

if [ -f "/home/ga/Documents/RS44_passes.txt" ]; then
    RS44_EXISTS="true"
    MTIME=$(stat -c %Y "/home/ga/Documents/RS44_passes.txt" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        RS44_CREATED_DURING="true"
    fi
    RS44_CONTENT=$(head -n 20 "/home/ga/Documents/RS44_passes.txt" | tr '\n' '|' | tr -d '\r' | sed 's/"/\\"/g')
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/rf_pass_prediction_export_result.json << EOF
{
    "dallas_exists": $DALLAS_EXISTS,
    "dallas_lat": "$(escape_json "$DALLAS_LAT")",
    "dallas_lon": "$(escape_json "$DALLAS_LON")",
    "dallas_alt": "$(escape_json "$DALLAS_ALT")",
    "field_mod_exists": $FIELD_MOD_EXISTS,
    "field_satellites": "$(escape_json "$FIELD_SATELLITES")",
    "field_qthfile": "$(escape_json "$FIELD_QTHFILE")",
    "field_showmap": "$(escape_json "$SHOWMAP")",
    "field_showpolarplot": "$(escape_json "$SHOWPOLARPLOT")",
    "fo29_exists": $FO29_EXISTS,
    "fo29_created_during": $FO29_CREATED_DURING,
    "fo29_content": "$(escape_json "$FO29_CONTENT")",
    "rs44_exists": $RS44_EXISTS,
    "rs44_created_during": $RS44_CREATED_DURING,
    "rs44_content": "$(escape_json "$RS44_CONTENT")"
}
EOF

echo "Result saved to /tmp/rf_pass_prediction_export_result.json"
cat /tmp/rf_pass_prediction_export_result.json
echo ""
echo "=== Export Complete ==="