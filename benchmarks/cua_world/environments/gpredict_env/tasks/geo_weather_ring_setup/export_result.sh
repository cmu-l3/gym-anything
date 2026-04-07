#!/bin/bash
echo "=== Exporting geo_weather_ring_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final_screenshot.png 2>/dev/null || true

WALLOPS_EXISTS="false"
WALLOPS_LAT=""
WALLOPS_LON=""
WALLOPS_ALT=""
WALLOPS_QTH_NAME=""

DARMSTADT_EXISTS="false"
DARMSTADT_LAT=""
DARMSTADT_LON=""
DARMSTADT_ALT=""
DARMSTADT_QTH_NAME=""

MELBOURNE_EXISTS="false"
MELBOURNE_LAT=""
MELBOURNE_LON=""
MELBOURNE_ALT=""
MELBOURNE_QTH_NAME=""

# Scan QTH files
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename=$(basename "$qth" .qth)
    
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    alt=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    
    lat_int=$(echo "$lat" | cut -d. -f1 | tr -d '-')
    lon_int=$(echo "$lon" | cut -d. -f1 | tr -d '-')
    
    # Check for Wallops Island
    if echo "$basename" | grep -qi "wallops" || { [ "$lat_int" = "37" ] && [ "$lon_int" = "75" ]; }; then
        WALLOPS_EXISTS="true"
        WALLOPS_LAT="$lat"
        WALLOPS_LON="$lon"
        WALLOPS_ALT="$alt"
        WALLOPS_QTH_NAME="$(basename "$qth")"
    fi
    
    # Check for Darmstadt
    if echo "$basename" | grep -qi "darmstadt" || { [ "$lat_int" = "49" ] && [ "$lon_int" = "8" ]; }; then
        DARMSTADT_EXISTS="true"
        DARMSTADT_LAT="$lat"
        DARMSTADT_LON="$lon"
        DARMSTADT_ALT="$alt"
        DARMSTADT_QTH_NAME="$(basename "$qth")"
    fi
    
    # Check for Melbourne
    if echo "$basename" | grep -qi "melbourne" || { [ "$lat_int" = "37" ] && [ "$lon_int" = "144" ]; }; then
        MELBOURNE_EXISTS="true"
        MELBOURNE_LAT="$lat"
        MELBOURNE_LON="$lon"
        MELBOURNE_ALT="$alt"
        MELBOURNE_QTH_NAME="$(basename "$qth")"
    fi
done

# Scan Modules
GEO_WEATHER_EXISTS="false"
GEO_WEATHER_SATS=""
GEO_WEATHER_QTH=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    basename=$(basename "$mod" .mod)
    if echo "$basename" | grep -qi "geo\|weather"; then
        GEO_WEATHER_EXISTS="true"
        GEO_WEATHER_SATS=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        GEO_WEATHER_QTH=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2)
        break
    fi
done

# Check Default QTH
DEFAULT_QTH=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '\r')
fi

# Check Pittsburgh
PITTSBURGH_EXISTS="false"
if [ -f "${GPREDICT_CONF_DIR}/Pittsburgh.qth" ]; then
    PITTSBURGH_EXISTS="true"
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/geo_weather_ring_setup_result.json << EOF
{
    "wallops_exists": $WALLOPS_EXISTS,
    "wallops_lat": "$(escape_json "$WALLOPS_LAT")",
    "wallops_lon": "$(escape_json "$WALLOPS_LON")",
    "wallops_alt": "$(escape_json "$WALLOPS_ALT")",
    "wallops_qth_name": "$(escape_json "$WALLOPS_QTH_NAME")",
    "darmstadt_exists": $DARMSTADT_EXISTS,
    "darmstadt_lat": "$(escape_json "$DARMSTADT_LAT")",
    "darmstadt_lon": "$(escape_json "$DARMSTADT_LON")",
    "darmstadt_alt": "$(escape_json "$DARMSTADT_ALT")",
    "darmstadt_qth_name": "$(escape_json "$DARMSTADT_QTH_NAME")",
    "melbourne_exists": $MELBOURNE_EXISTS,
    "melbourne_lat": "$(escape_json "$MELBOURNE_LAT")",
    "melbourne_lon": "$(escape_json "$MELBOURNE_LON")",
    "melbourne_alt": "$(escape_json "$MELBOURNE_ALT")",
    "melbourne_qth_name": "$(escape_json "$MELBOURNE_QTH_NAME")",
    "geo_weather_exists": $GEO_WEATHER_EXISTS,
    "geo_weather_sats": "$(escape_json "$GEO_WEATHER_SATS")",
    "geo_weather_qth": "$(escape_json "$GEO_WEATHER_QTH")",
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "pittsburgh_exists": $PITTSBURGH_EXISTS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/geo_weather_ring_setup_result.json"
cat /tmp/geo_weather_ring_setup_result.json
echo ""
echo "=== Export Complete ==="