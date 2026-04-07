#!/bin/bash
echo "=== Exporting automated_gs_hardware_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_RADIOS_DIR="${GPREDICT_CONF_DIR}/radios"
GPREDICT_ROTORS_DIR="${GPREDICT_CONF_DIR}/rotors"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Radios ---
RADIO_EXISTS="false"
RADIO_HOST=""
RADIO_PORT=""
RADIO_TYPE=""

for rig in "${GPREDICT_RADIOS_DIR}"/*.rig; do
    [ -f "$rig" ] || continue
    RADIO_EXISTS="true"
    RADIO_HOST=$(grep -i "^HOST=" "$rig" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    RADIO_PORT=$(grep -i "^PORT=" "$rig" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    RADIO_TYPE=$(grep -i "^TYPE=" "$rig" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    break
done

# --- Rotors ---
ROTOR_EXISTS="false"
ROTOR_HOST=""
ROTOR_PORT=""

for rot in "${GPREDICT_ROTORS_DIR}"/*.rot; do
    [ -f "$rot" ] || continue
    ROTOR_EXISTS="true"
    ROTOR_HOST=$(grep -i "^HOST=" "$rot" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    ROTOR_PORT=$(grep -i "^PORT=" "$rot" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    break
done

# --- Stanford QTH (lat ~37.4) ---
STANFORD_EXISTS="false"
STANFORD_LAT=""
STANFORD_LON=""
STANFORD_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "37" ]; then
        STANFORD_EXISTS="true"
        STANFORD_LAT="$lat"
        STANFORD_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        STANFORD_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- TLE Auto Update ---
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
GPREDICT_CFG_CONTENT=""
if [ -f "$GPREDICT_CFG" ]; then
    GPREDICT_CFG_CONTENT=$(cat "$GPREDICT_CFG" | tr '\n' '|' | sed 's/"/\\"/g')
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/automated_gs_hardware_setup_result.json << EOF
{
    "radio_exists": $RADIO_EXISTS,
    "radio_host": "$(escape_json "$RADIO_HOST")",
    "radio_port": "$(escape_json "$RADIO_PORT")",
    "radio_type": "$(escape_json "$RADIO_TYPE")",
    "rotor_exists": $ROTOR_EXISTS,
    "rotor_host": "$(escape_json "$ROTOR_HOST")",
    "rotor_port": "$(escape_json "$ROTOR_PORT")",
    "stanford_exists": $STANFORD_EXISTS,
    "stanford_lat": "$(escape_json "$STANFORD_LAT")",
    "stanford_lon": "$(escape_json "$STANFORD_LON")",
    "stanford_alt": "$(escape_json "$STANFORD_ALT")",
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/automated_gs_hardware_setup_result.json"
cat /tmp/automated_gs_hardware_setup_result.json
echo ""
echo "=== Export Complete ==="