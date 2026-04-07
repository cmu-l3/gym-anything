#!/bin/bash
set -e

echo "=== Exporting legacy_cleanup_qth_override result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Check deleted modules and amateur module
TEST1_EXISTS="false"
TEST2_EXISTS="false"
AMATEUR_EXISTS="false"

if [ -f "${GPREDICT_MOD_DIR}/TestModule1.mod" ]; then TEST1_EXISTS="true"; fi
if [ -f "${GPREDICT_MOD_DIR}/TestModule2.mod" ]; then TEST2_EXISTS="true"; fi
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then AMATEUR_EXISTS="true"; fi

# Extract LEO_Comms module data
LEO_COMMS_EXISTS="false"
LEO_COMMS_SATELLITES=""
LEO_COMMS_QTHFILE=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "leo.*com"; then
        LEO_COMMS_EXISTS="true"
        LEO_COMMS_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\n\r')
        LEO_COMMS_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\n\r')
        break
    fi
done

# Extract ground stations
WS_EXISTS="false"
WS_FILENAME=""
WS_LAT=""
WS_LON=""
WS_ALT=""

WI_EXISTS="false"
WI_FILENAME=""
WI_LAT=""
WI_LON=""
WI_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth")
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)

    # White Sands is ~32.5N
    if [ "$lat_int" = "32" ]; then
        WS_EXISTS="true"
        WS_FILENAME="$basename_qth"
        WS_LAT="$lat"
        WS_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        WS_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    fi

    # Wallops Island is ~37.9N
    if [ "$lat_int" = "37" ]; then
        WI_EXISTS="true"
        WI_FILENAME="$basename_qth"
        WI_LAT="$lat"
        WI_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        WI_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    fi
done

# Extract default QTH from gpredict.cfg
DEFAULT_QTH=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '\n\r')
fi

# Escape helper
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/legacy_cleanup_result.json << EOF
{
    "test1_exists": $TEST1_EXISTS,
    "test2_exists": $TEST2_EXISTS,
    "amateur_exists": $AMATEUR_EXISTS,
    "leo_comms_exists": $LEO_COMMS_EXISTS,
    "leo_comms_satellites": "$(escape_json "$LEO_COMMS_SATELLITES")",
    "leo_comms_qthfile": "$(escape_json "$LEO_COMMS_QTHFILE")",
    "ws_exists": $WS_EXISTS,
    "ws_filename": "$(escape_json "$WS_FILENAME")",
    "ws_lat": "$(escape_json "$WS_LAT")",
    "ws_lon": "$(escape_json "$WS_LON")",
    "ws_alt": "$(escape_json "$WS_ALT")",
    "wi_exists": $WI_EXISTS,
    "wi_filename": "$(escape_json "$WI_FILENAME")",
    "wi_lat": "$(escape_json "$WI_LAT")",
    "wi_lon": "$(escape_json "$WI_LON")",
    "wi_alt": "$(escape_json "$WI_ALT")",
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/legacy_cleanup_result.json"
cat /tmp/legacy_cleanup_result.json
echo ""
echo "=== Export Complete ==="