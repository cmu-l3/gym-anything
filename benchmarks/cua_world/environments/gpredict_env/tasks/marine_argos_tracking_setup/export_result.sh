#!/bin/bash
echo "=== Exporting marine_argos_tracking_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check if Amateur.mod exists ---
AMATEUR_EXISTS="false"
if ls "${GPREDICT_MOD_DIR}"/*.mod 2>/dev/null | grep -qi "amateur"; then
    AMATEUR_EXISTS="true"
fi

# --- Read Argos_Tracking.mod ---
ARGOS_EXISTS="false"
ARGOS_SATELLITES=""
ARGOS_QTHFILE=""
ARGOS_SHOWMAP=""
ARGOS_SHOWPOLARPLOT=""
ARGOS_LAYOUT=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "argos"; then
        ARGOS_EXISTS="true"
        ARGOS_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        ARGOS_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        ARGOS_SHOWMAP=$(grep -i "^SHOWMAP=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        ARGOS_SHOWPOLARPLOT=$(grep -i "^SHOWPOLARPLOT=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        ARGOS_LAYOUT=$(grep -i "^LAYOUT=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Read Galapagos QTH (scan by lat ~ -0.74) ---
GALAPAGOS_EXISTS="false"
GALAPAGOS_LAT=""
GALAPAGOS_LON=""
GALAPAGOS_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    
    # Use python to check if lat is near -0.74
    is_galapagos=$(python3 -c "print('true' if abs(float('$lat' or 0) - (-0.74)) < 0.2 else 'false')" 2>/dev/null || echo "false")
    
    if [ "$is_galapagos" = "true" ]; then
        GALAPAGOS_EXISTS="true"
        GALAPAGOS_LAT="$lat"
        GALAPAGOS_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        GALAPAGOS_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Read Ascension QTH (scan by lat ~ -7.9) ---
ASCENSION_EXISTS="false"
ASCENSION_LAT=""
ASCENSION_LON=""
ASCENSION_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    
    is_ascension=$(python3 -c "print('true' if abs(float('$lat' or 0) - (-7.94)) < 0.2 else 'false')" 2>/dev/null || echo "false")
    
    if [ "$is_ascension" = "true" ]; then
        ASCENSION_EXISTS="true"
        ASCENSION_LAT="$lat"
        ASCENSION_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        ASCENSION_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Check metric units in gpredict.cfg ---
METRIC_UNITS="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    UNIT_VAL=$(grep -i "^unit=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UNIT_VAL" = "0" ]; then
        METRIC_UNITS="true"
    fi
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/marine_argos_tracking_result.json << EOF
{
    "amateur_exists": $AMATEUR_EXISTS,
    "argos_exists": $ARGOS_EXISTS,
    "argos_satellites": "$(escape_json "$ARGOS_SATELLITES")",
    "argos_qthfile": "$(escape_json "$ARGOS_QTHFILE")",
    "argos_showmap": "$(escape_json "$ARGOS_SHOWMAP")",
    "argos_showpolarplot": "$(escape_json "$ARGOS_SHOWPOLARPLOT")",
    "argos_layout": "$(escape_json "$ARGOS_LAYOUT")",
    "galapagos_exists": $GALAPAGOS_EXISTS,
    "galapagos_lat": "$(escape_json "$GALAPAGOS_LAT")",
    "galapagos_lon": "$(escape_json "$GALAPAGOS_LON")",
    "galapagos_alt": "$(escape_json "$GALAPAGOS_ALT")",
    "ascension_exists": $ASCENSION_EXISTS,
    "ascension_lat": "$(escape_json "$ASCENSION_LAT")",
    "ascension_lon": "$(escape_json "$ASCENSION_LON")",
    "ascension_alt": "$(escape_json "$ASCENSION_ALT")",
    "metric_units_enabled": $METRIC_UNITS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/marine_argos_tracking_result.json"
cat /tmp/marine_argos_tracking_result.json
echo ""
echo "=== Export Complete ==="