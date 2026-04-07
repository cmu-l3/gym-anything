#!/bin/bash
# Export script for control_room_dashboards task

echo "=== Exporting control_room_dashboards result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check if Amateur.mod was deleted ---
AMATEUR_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_EXISTS="true"
fi

# --- Read GEO_WX.mod ---
GEO_WX_EXISTS="false"
GEO_WX_SATELLITES=""
GEO_WX_QTH=""
GEO_WX_LAYOUT=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "geo"; then
        GEO_WX_EXISTS="true"
        GEO_WX_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        GEO_WX_QTH=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        GEO_WX_LAYOUT=$(grep -i "^LAYOUT=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        break
    fi
done

# --- Read LEO_WX.mod ---
LEO_WX_EXISTS="false"
LEO_WX_SATELLITES=""
LEO_WX_QTH=""
LEO_WX_LAYOUT=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "leo"; then
        LEO_WX_EXISTS="true"
        LEO_WX_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        LEO_WX_QTH=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        LEO_WX_LAYOUT=$(grep -i "^LAYOUT=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        break
    fi
done

# --- Read Miami_NHC QTH (lat ~25.7) ---
MIAMI_EXISTS="false"
MIAMI_LAT=""
MIAMI_LON=""
MIAMI_ALT=""
MIAMI_QTH_FILENAME=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth")
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "25" ]; then
        MIAMI_EXISTS="true"
        MIAMI_QTH_FILENAME="$basename_qth"
        MIAMI_LAT="$lat"
        MIAMI_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        MIAMI_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Check UTC time setting in gpredict.cfg ---
UTC_TIME_ENABLED="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    UTC_VAL=$(grep -i "^utc=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UTC_VAL" = "1" ]; then
        UTC_TIME_ENABLED="true"
    fi
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/control_room_dashboards_result.json << EOF
{
    "amateur_exists": $AMATEUR_EXISTS,
    "geo_wx_exists": $GEO_WX_EXISTS,
    "geo_wx_satellites": "$(escape_json "$GEO_WX_SATELLITES")",
    "geo_wx_qth": "$(escape_json "$GEO_WX_QTH")",
    "geo_wx_layout": "$(escape_json "$GEO_WX_LAYOUT")",
    "leo_wx_exists": $LEO_WX_EXISTS,
    "leo_wx_satellites": "$(escape_json "$LEO_WX_SATELLITES")",
    "leo_wx_qth": "$(escape_json "$LEO_WX_QTH")",
    "leo_wx_layout": "$(escape_json "$LEO_WX_LAYOUT")",
    "miami_exists": $MIAMI_EXISTS,
    "miami_qth_filename": "$(escape_json "$MIAMI_QTH_FILENAME")",
    "miami_lat": "$(escape_json "$MIAMI_LAT")",
    "miami_lon": "$(escape_json "$MIAMI_LON")",
    "miami_alt": "$(escape_json "$MIAMI_ALT")",
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/control_room_dashboards_result.json"
cat /tmp/control_room_dashboards_result.json
echo ""
echo "=== Export Complete ==="