#!/bin/bash
# Export script for atmospheric_diurnal_tracking_setup task

echo "=== Exporting atmospheric_diurnal_tracking_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Find Taipei Ground Station ---
TAIPEI_QTH=""
TAIPEI_LAT=""
TAIPEI_LON=""
TAIPEI_ALT=""
TAIPEI_EXISTS="false"

# Search for any QTH file near Taipei (LAT ~25)
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "25" ]; then
        TAIPEI_EXISTS="true"
        TAIPEI_QTH="$(basename "$qth")"
        TAIPEI_LAT="$lat"
        TAIPEI_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        TAIPEI_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Check COSMIC-2 Module ---
COSMIC_MOD_NAME=""
COSMIC_EXISTS="false"
COSMIC_SATELLITES=""
COSMIC_CONTENT=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "cosmic"; then
        COSMIC_EXISTS="true"
        COSMIC_MOD_NAME="$modname"
        COSMIC_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        # Extract full module content for verifier to check map-specific preferences
        COSMIC_CONTENT=$(cat "$mod" | tr '\n' '|' | sed 's/"/\\"/g' | tr -d '\r')
        break
    fi
done

# --- Read gpredict.cfg preferences ---
GPREDICT_CFG_CONTENT=""
DEFAULT_QTH=""
UTC_TIME="false"

if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    GPREDICT_CFG_CONTENT=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | tr '\n' '|' | sed 's/"/\\"/g' | tr -d '\r')
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    UTC_VAL=$(grep -i "^utc=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UTC_VAL" = "1" ]; then
        UTC_TIME="true"
    fi
fi

# Escape JSON strings
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/atmospheric_diurnal_result.json << EOF
{
    "taipei_exists": $TAIPEI_EXISTS,
    "taipei_qth_file": "$(escape_json "$TAIPEI_QTH")",
    "taipei_lat": "$(escape_json "$TAIPEI_LAT")",
    "taipei_lon": "$(escape_json "$TAIPEI_LON")",
    "taipei_alt": "$(escape_json "$TAIPEI_ALT")",
    "cosmic_exists": $COSMIC_EXISTS,
    "cosmic_mod_name": "$(escape_json "$COSMIC_MOD_NAME")",
    "cosmic_satellites": "$(escape_json "$COSMIC_SATELLITES")",
    "cosmic_content": "$(escape_json "$COSMIC_CONTENT")",
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "utc_time_enabled": $UTC_TIME,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/atmospheric_diurnal_result.json"
echo "=== Export Complete ==="