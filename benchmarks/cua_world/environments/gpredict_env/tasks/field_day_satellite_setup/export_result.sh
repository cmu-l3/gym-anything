#!/bin/bash
echo "=== Exporting field_day_satellite_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Read Tussey_Mountain.qth ---
TM_EXISTS="false"
TM_LAT=""
TM_LON=""
TM_ALT=""
TM_MTIME=0

# Search for any QTH file resembling Tussey_Mountain
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    if echo "$basename_qth" | grep -qi "tussey"; then
        TM_EXISTS="true"
        TM_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        TM_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        TM_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        TM_MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
        break
    fi
done

# If not found by name, scan by latitude ~40.7
if [ "$TM_EXISTS" = "false" ]; then
    for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
        [ -f "$qth" ] || continue
        lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lat_int=$(echo "$lat" | cut -d. -f1)
        if [ "$lat_int" = "40" ]; then
            lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            lon_abs=$(echo "$lon" | sed 's/-//')
            lon_int=$(echo "$lon_abs" | cut -d. -f1)
            if [ "$lon_int" = "77" ]; then
                TM_EXISTS="true"
                TM_LAT="$lat"
                TM_LON="$lon"
                TM_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
                TM_MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
                break
            fi
        fi
    done
fi

# --- Read FieldDay.mod ---
FIELDDAY_EXISTS="false"
FIELDDAY_SATELLITES=""
FIELDDAY_QTHFILE=""
FIELDDAY_MTIME=0

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "field\|day"; then
        FIELDDAY_EXISTS="true"
        FIELDDAY_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        FIELDDAY_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2)
        FIELDDAY_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        break
    fi
done

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

cat > /tmp/field_day_satellite_setup_result.json << EOF
{
    "task_start": $TASK_START,
    "tm_exists": $TM_EXISTS,
    "tm_lat": "$(escape_json "$TM_LAT")",
    "tm_lon": "$(escape_json "$TM_LON")",
    "tm_alt": "$(escape_json "$TM_ALT")",
    "tm_mtime": $TM_MTIME,
    "fieldday_exists": $FIELDDAY_EXISTS,
    "fieldday_satellites": "$(escape_json "$FIELDDAY_SATELLITES")",
    "fieldday_qthfile": "$(escape_json "$FIELDDAY_QTHFILE")",
    "fieldday_mtime": $FIELDDAY_MTIME,
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/field_day_satellite_setup_result.json"
cat /tmp/field_day_satellite_setup_result.json
echo ""
echo "=== Export Complete ==="