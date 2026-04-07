#!/bin/bash
echo "=== Exporting launch_range_safety_cola result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Capture final screenshot for VLM layout verification
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# --- Ground Stations Check ---
WALLOPS_EXISTS="false"
WALLOPS_LAT=""
WALLOPS_LON=""
WALLOPS_ALT=""
WALLOPS_QTH_FILENAME=""

BERMUDA_EXISTS="false"
BERMUDA_LAT=""
BERMUDA_LON=""
BERMUDA_ALT=""

ANTIGUA_EXISTS="false"
ANTIGUA_LAT=""
ANTIGUA_LON=""
ANTIGUA_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    
    # Extract properties
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1 | sed 's/[^0-9-]//g')
    
    lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lon_abs=$(echo "$lon" | sed 's/-//')
    lon_int=$(echo "$lon_abs" | cut -d. -f1 | sed 's/[^0-9-]//g')
    
    alt=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    
    # Check if matches Wallops (lat ~ 37, lon ~ 75)
    if [ "$lat_int" = "37" ] && [ "$lon_int" = "75" ]; then
        WALLOPS_EXISTS="true"
        WALLOPS_LAT="$lat"
        WALLOPS_LON="$lon"
        WALLOPS_ALT="$alt"
        WALLOPS_QTH_FILENAME=$(basename "$qth")
        
    # Check if matches Bermuda (lat ~ 32, lon ~ 64)
    elif [ "$lat_int" = "32" ] && [ "$lon_int" = "64" ]; then
        BERMUDA_EXISTS="true"
        BERMUDA_LAT="$lat"
        BERMUDA_LON="$lon"
        BERMUDA_ALT="$alt"
        
    # Check if matches Antigua (lat ~ 17, lon ~ 61)
    elif [ "$lat_int" = "17" ] && [ "$lon_int" = "61" ]; then
        ANTIGUA_EXISTS="true"
        ANTIGUA_LAT="$lat"
        ANTIGUA_LON="$lon"
        ANTIGUA_ALT="$alt"
    fi
done

# --- COLA_Monitoring Module Check ---
COLA_EXISTS="false"
COLA_SATELLITES=""
COLA_QTHFILE=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "cola"; then
        COLA_EXISTS="true"
        COLA_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\n\r')
        COLA_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\n\r')
        break
    fi
done

# --- UTC Setting Check ---
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

# Utility function to escape JSON content
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/launch_range_safety_cola_result.json << EOF
{
    "wallops_exists": $WALLOPS_EXISTS,
    "wallops_lat": "$(escape_json "$WALLOPS_LAT")",
    "wallops_lon": "$(escape_json "$WALLOPS_LON")",
    "wallops_alt": "$(escape_json "$WALLOPS_ALT")",
    "wallops_qth_filename": "$(escape_json "$WALLOPS_QTH_FILENAME")",
    "bermuda_exists": $BERMUDA_EXISTS,
    "bermuda_lat": "$(escape_json "$BERMUDA_LAT")",
    "bermuda_lon": "$(escape_json "$BERMUDA_LON")",
    "bermuda_alt": "$(escape_json "$BERMUDA_ALT")",
    "antigua_exists": $ANTIGUA_EXISTS,
    "antigua_lat": "$(escape_json "$ANTIGUA_LAT")",
    "antigua_lon": "$(escape_json "$ANTIGUA_LON")",
    "antigua_alt": "$(escape_json "$ANTIGUA_ALT")",
    "cola_exists": $COLA_EXISTS,
    "cola_satellites": "$(escape_json "$COLA_SATELLITES")",
    "cola_qthfile": "$(escape_json "$COLA_QTHFILE")",
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/launch_range_safety_cola_result.json"
cat /tmp/launch_range_safety_cola_result.json
echo ""
echo "=== Export Complete ==="