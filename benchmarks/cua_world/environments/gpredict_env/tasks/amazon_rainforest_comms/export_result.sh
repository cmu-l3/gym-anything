#!/bin/bash
# Export script for amazon_rainforest_comms task

echo "=== Exporting amazon_rainforest_comms result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Function to check if file was modified after task start
file_modified_during_task() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
            return
        fi
    fi
    echo "false"
}

# --- Read Tiputini QTH ---
TIPUTINI_EXISTS="false"
TIPUTINI_LAT=""
TIPUTINI_LON=""
TIPUTINI_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1 | sed 's/-//')
    
    # Check by filename OR lat ~0
    if echo "$basename_qth" | grep -qi "tiputini" || [ "$lat_int" = "0" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | sed 's/-//' | cut -d. -f1)
        if echo "$basename_qth" | grep -qi "tiputini" || [ "$lon_int" = "76" ]; then
            TIPUTINI_EXISTS="true"
            TIPUTINI_LAT="$lat"
            TIPUTINI_LON="$lon"
            TIPUTINI_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Read Manaus QTH ---
MANAUS_EXISTS="false"
MANAUS_LAT=""
MANAUS_LON=""
MANAUS_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1 | sed 's/-//')
    
    if echo "$basename_qth" | grep -qi "manaus" || [ "$lat_int" = "3" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | sed 's/-//' | cut -d. -f1)
        if echo "$basename_qth" | grep -qi "manaus" || [ "$lon_int" = "60" ]; then
            MANAUS_EXISTS="true"
            MANAUS_LAT="$lat"
            MANAUS_LON="$lon"
            MANAUS_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Check Pittsburgh.qth deleted ---
PITTSBURGH_EXISTS="false"
if [ -f "${GPREDICT_CONF_DIR}/Pittsburgh.qth" ]; then
    PITTSBURGH_EXISTS="true"
fi

# --- Read Bio_Relay.mod ---
BIO_RELAY_EXISTS="false"
BIO_RELAY_SATELLITES=""
BIO_RELAY_CREATED_DURING_TASK="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "bio\|relay"; then
        BIO_RELAY_EXISTS="true"
        BIO_RELAY_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        BIO_RELAY_CREATED_DURING_TASK=$(file_modified_during_task "$mod")
        break
    fi
done

# --- Read Trop_Weather.mod ---
TROP_WEATHER_EXISTS="false"
TROP_WEATHER_SATELLITES=""
TROP_WEATHER_CREATED_DURING_TASK="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "trop\|weather\|wx"; then
        TROP_WEATHER_EXISTS="true"
        TROP_WEATHER_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        TROP_WEATHER_CREATED_DURING_TASK=$(file_modified_during_task "$mod")
        break
    fi
done

# --- Check Default QTH ---
DEFAULT_QTH=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/amazon_rainforest_comms_result.json << EOF
{
    "tiputini_exists": $TIPUTINI_EXISTS,
    "tiputini_lat": "$(escape_json "$TIPUTINI_LAT")",
    "tiputini_lon": "$(escape_json "$TIPUTINI_LON")",
    "tiputini_alt": "$(escape_json "$TIPUTINI_ALT")",
    "manaus_exists": $MANAUS_EXISTS,
    "manaus_lat": "$(escape_json "$MANAUS_LAT")",
    "manaus_lon": "$(escape_json "$MANAUS_LON")",
    "manaus_alt": "$(escape_json "$MANAUS_ALT")",
    "pittsburgh_exists": $PITTSBURGH_EXISTS,
    "bio_relay_exists": $BIO_RELAY_EXISTS,
    "bio_relay_satellites": "$(escape_json "$BIO_RELAY_SATELLITES")",
    "bio_relay_created_during_task": $BIO_RELAY_CREATED_DURING_TASK,
    "trop_weather_exists": $TROP_WEATHER_EXISTS,
    "trop_weather_satellites": "$(escape_json "$TROP_WEATHER_SATELLITES")",
    "trop_weather_created_during_task": $TROP_WEATHER_CREATED_DURING_TASK,
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/amazon_rainforest_comms_result.json"
cat /tmp/amazon_rainforest_comms_result.json
echo ""
echo "=== Export Complete ==="