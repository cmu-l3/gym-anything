#!/bin/bash
# Export script for antarctic_field_season_planning task

echo "=== Exporting antarctic_field_season_planning result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# --- Read Palmer Station QTH (lat ~ -64.7) ---
PALMER_EXISTS="false"
PALMER_FILENAME=""
PALMER_LAT=""
PALMER_LON=""
PALMER_ALT=""
PALMER_MTIME="0"

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    # Check for latitude near -64
    if [ "$lat_int" = "-64" ] || [ "$lat_int" = "-65" ]; then
        PALMER_EXISTS="true"
        PALMER_FILENAME=$(basename "$qth")
        PALMER_LAT="$lat"
        PALMER_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        PALMER_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        PALMER_MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
        break
    fi
done

# --- Read Punta Arenas QTH (lat ~ -53.1) ---
PUNTA_EXISTS="false"
PUNTA_FILENAME=""
PUNTA_LAT=""
PUNTA_LON=""
PUNTA_ALT=""
PUNTA_MTIME="0"

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "-53" ]; then
        PUNTA_EXISTS="true"
        PUNTA_FILENAME=$(basename "$qth")
        PUNTA_LAT="$lat"
        PUNTA_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        PUNTA_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        PUNTA_MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
        break
    fi
done

# --- Read PalmerComms Module ---
COMMS_EXISTS="false"
COMMS_FILENAME=""
COMMS_SATS=""
COMMS_QTHFILE=""
COMMS_MTIME="0"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "comms\|palmercomms"; then
        COMMS_EXISTS="true"
        COMMS_FILENAME=$(basename "$mod")
        COMMS_SATS=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        COMMS_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r\n')
        COMMS_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        break
    fi
done

# --- Read PalmerWX Module ---
WX_EXISTS="false"
WX_FILENAME=""
WX_SATS=""
WX_QTHFILE=""
WX_MTIME="0"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "wx\|palmerwx"; then
        WX_EXISTS="true"
        WX_FILENAME=$(basename "$mod")
        WX_SATS=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        WX_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r\n')
        WX_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        break
    fi
done

# --- Check DEFAULT_QTH in global config ---
DEFAULT_QTH=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '\r\n')
fi

# --- Preservation checks ---
PITTSBURGH_EXISTS=$([ -f "${GPREDICT_CONF_DIR}/Pittsburgh.qth" ] && echo "true" || echo "false")
AMATEUR_EXISTS=$([ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/antarctic_field_season_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "palmer": {
        "exists": $PALMER_EXISTS,
        "filename": "$(escape_json "$PALMER_FILENAME")",
        "lat": "$(escape_json "$PALMER_LAT")",
        "lon": "$(escape_json "$PALMER_LON")",
        "alt": "$(escape_json "$PALMER_ALT")",
        "mtime": $PALMER_MTIME
    },
    "punta": {
        "exists": $PUNTA_EXISTS,
        "filename": "$(escape_json "$PUNTA_FILENAME")",
        "lat": "$(escape_json "$PUNTA_LAT")",
        "lon": "$(escape_json "$PUNTA_LON")",
        "alt": "$(escape_json "$PUNTA_ALT")",
        "mtime": $PUNTA_MTIME
    },
    "comms": {
        "exists": $COMMS_EXISTS,
        "filename": "$(escape_json "$COMMS_FILENAME")",
        "satellites": "$(escape_json "$COMMS_SATS")",
        "qthfile": "$(escape_json "$COMMS_QTHFILE")",
        "mtime": $COMMS_MTIME
    },
    "wx": {
        "exists": $WX_EXISTS,
        "filename": "$(escape_json "$WX_FILENAME")",
        "satellites": "$(escape_json "$WX_SATS")",
        "qthfile": "$(escape_json "$WX_QTHFILE")",
        "mtime": $WX_MTIME
    },
    "global": {
        "default_qth": "$(escape_json "$DEFAULT_QTH")"
    },
    "preservation": {
        "pittsburgh_exists": $PITTSBURGH_EXISTS,
        "amateur_exists": $AMATEUR_EXISTS
    },
    "export_timestamp": $(date +%s)
}
EOF

rm -f /tmp/antarctic_field_season_result.json 2>/dev/null || sudo rm -f /tmp/antarctic_field_season_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/antarctic_field_season_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/antarctic_field_season_result.json
chmod 666 /tmp/antarctic_field_season_result.json 2>/dev/null || sudo chmod 666 /tmp/antarctic_field_season_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/antarctic_field_season_result.json"
cat /tmp/antarctic_field_season_result.json
echo ""
echo "=== Export Complete ==="