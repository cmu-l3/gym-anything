#!/bin/bash
# Export script for sota_high_altitude_expedition task

echo "=== Exporting sota_high_altitude_expedition result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Scan for Mount Whitney QTH (latitude ~36.5) ---
MT_WHITNEY_EXISTS="false"
MT_WHITNEY_QTH_FILENAME=""
MT_WHITNEY_LAT=""
MT_WHITNEY_LON=""
MT_WHITNEY_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    
    # Mt. Whitney latitude is 36.5786
    if [ "$lat_int" = "36" ] || echo "$(basename "$qth")" | grep -qi "whitney"; then
        MT_WHITNEY_EXISTS="true"
        MT_WHITNEY_QTH_FILENAME=$(basename "$qth")
        MT_WHITNEY_LAT="$lat"
        MT_WHITNEY_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        MT_WHITNEY_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Scan for SOTA_FM module ---
SOTA_FM_EXISTS="false"
SOTA_FM_SATS=""
SOTA_FM_QTH=""
SOTA_FM_MAP=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    
    if echo "$modname" | grep -qi "sota"; then
        SOTA_FM_EXISTS="true"
        SOTA_FM_SATS=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        SOTA_FM_QTH=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        SOTA_FM_MAP=$(grep -i "^MAP_FILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Check Global Preferences in gpredict.cfg ---
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
GLOBAL_MAP=""
AUTO_UPDATE="false"
CFG_CONTENT=""

if [ -f "$GPREDICT_CFG" ]; then
    GLOBAL_MAP=$(grep -i "^MAP_FILE=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    
    # Check for TLE background update setting (AUTO_UPDATE=True or 1)
    if grep -qi "^AUTO_UPDATE=\(true\|1\)" "$GPREDICT_CFG"; then
        AUTO_UPDATE="true"
    fi
    
    # Store full config dump for robust verifier checks
    CFG_CONTENT=$(cat "$GPREDICT_CFG" | tr '\n' '|' | sed 's/"/\\"/g')
fi

# Escape JSON strings
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/sota_high_altitude_expedition_result.json << EOF
{
    "mt_whitney_exists": $MT_WHITNEY_EXISTS,
    "mt_whitney_filename": "$(escape_json "$MT_WHITNEY_QTH_FILENAME")",
    "mt_whitney_lat": "$(escape_json "$MT_WHITNEY_LAT")",
    "mt_whitney_lon": "$(escape_json "$MT_WHITNEY_LON")",
    "mt_whitney_alt": "$(escape_json "$MT_WHITNEY_ALT")",
    "sota_fm_exists": $SOTA_FM_EXISTS,
    "sota_fm_sats": "$(escape_json "$SOTA_FM_SATS")",
    "sota_fm_qth": "$(escape_json "$SOTA_FM_QTH")",
    "sota_fm_map": "$(escape_json "$SOTA_FM_MAP")",
    "global_map": "$(escape_json "$GLOBAL_MAP")",
    "auto_update_enabled": $AUTO_UPDATE,
    "gpredict_cfg_content": "$(escape_json "$CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/sota_high_altitude_expedition_result.json"
cat /tmp/sota_high_altitude_expedition_result.json
echo ""
echo "=== Export Complete ==="