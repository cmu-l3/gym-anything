#!/bin/bash
# Export script for thermal_orbit_analysis_columns task

echo "=== Exporting thermal_orbit_analysis_columns result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check Amateur.mod ---
AMATEUR_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_EXISTS="true"
fi

# --- Check Thermal_Monitor.mod ---
THERMAL_EXISTS="false"
THERMAL_SATELLITES=""
THERMAL_HAS_ISS="false"
THERMAL_HAS_CSS="false"
THERMAL_SHOWMAP="1"
THERMAL_SHOWPOLARPLOT="1"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "thermal"; then
        THERMAL_EXISTS="true"
        THERMAL_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        if echo "$THERMAL_SATELLITES" | grep -q "25544"; then THERMAL_HAS_ISS="true"; fi
        if echo "$THERMAL_SATELLITES" | grep -q "48274"; then THERMAL_HAS_CSS="true"; fi
        
        # Check programmatic layout flags as fallback
        map_val=$(grep -i "^SHOWMAP=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        if [ -n "$map_val" ]; then THERMAL_SHOWMAP="$map_val"; fi
        
        polar_val=$(grep -i "^SHOWPOLARPLOT=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        if [ -n "$polar_val" ]; then THERMAL_SHOWPOLARPLOT="$polar_val"; fi
        break
    fi
done

# --- Check Imperial Units in gpredict.cfg ---
IMPERIAL_UNITS="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    UNIT_VAL=$(grep -i "^unit=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    # In GPredict, unit=1 means Imperial (Miles), unit=0 means Metric (Km)
    if [ "$UNIT_VAL" = "1" ] || [ "$UNIT_VAL" = "2" ]; then
        IMPERIAL_UNITS="true"
    fi
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/thermal_orbit_result.json << EOF
{
    "amateur_exists": $AMATEUR_EXISTS,
    "thermal_exists": $THERMAL_EXISTS,
    "thermal_satellites": "$(escape_json "$THERMAL_SATELLITES")",
    "thermal_has_iss": $THERMAL_HAS_ISS,
    "thermal_has_css": $THERMAL_HAS_CSS,
    "thermal_showmap": "$THERMAL_SHOWMAP",
    "thermal_showpolarplot": "$THERMAL_SHOWPOLARPLOT",
    "imperial_units_enabled": $IMPERIAL_UNITS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/thermal_orbit_result.json"
cat /tmp/thermal_orbit_result.json
echo ""
echo "=== Export Complete ==="