#!/bin/bash
echo "=== Exporting ILRS Laser Ranging result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check Matera QTH (lat ~40.6) ---
MATERA_EXISTS="false"
MATERA_LAT=""
MATERA_LON=""
MATERA_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "40" ]; then
        MATERA_EXISTS="true"
        MATERA_LAT="$lat"
        MATERA_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        MATERA_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Check Yarragadee QTH (lat ~-29.0) ---
YARRAGADEE_EXISTS="false"
YARRAGADEE_LAT=""
YARRAGADEE_LON=""
YARRAGADEE_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    # We need to preserve the exact string to check if it's properly negative (Southern hemisphere)
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    # Use awk/sed to safely extract integer part ignoring signs to find it loosely
    lat_int=$(echo "$lat" | sed 's/-//' | cut -d. -f1)
    
    if [ "$lat_int" = "29" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | sed 's/-//' | cut -d. -f1)
        if [ "$lon_int" = "115" ]; then
            YARRAGADEE_EXISTS="true"
            YARRAGADEE_LAT="$lat"
            YARRAGADEE_LON="$lon"
            YARRAGADEE_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Check ILRS_Targets.mod ---
ILRS_EXISTS="false"
ILRS_SATELLITES=""
ILRS_HAS_LAGEOS1="false"  # 8820
ILRS_HAS_LAGEOS2="false"  # 22195
ILRS_HAS_STARLETTE="false" # 7646
ILRS_HAS_STELLA="false"   # 22823
ILRS_HAS_LARES="false"    # 38077

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "ilrs\|laser\|target"; then
        ILRS_EXISTS="true"
        ILRS_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        
        if echo "$ILRS_SATELLITES" | grep -qE "8820|08820"; then ILRS_HAS_LAGEOS1="true"; fi
        if echo "$ILRS_SATELLITES" | grep -q "22195"; then ILRS_HAS_LAGEOS2="true"; fi
        if echo "$ILRS_SATELLITES" | grep -qE "7646|07646"; then ILRS_HAS_STARLETTE="true"; fi
        if echo "$ILRS_SATELLITES" | grep -q "22823"; then ILRS_HAS_STELLA="true"; fi
        if echo "$ILRS_SATELLITES" | grep -q "38077"; then ILRS_HAS_LARES="true"; fi
        break
    fi
done

# --- Check gpredict.cfg for MIN_EL and Metric Units ---
METRIC_UNITS="false"
MIN_EL="0"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    UNIT_VAL=$(grep -i "^unit=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UNIT_VAL" = "0" ]; then
        METRIC_UNITS="true"
    fi
    
    MIN_EL_VAL=$(grep -i "^MIN_EL=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ -n "$MIN_EL_VAL" ]; then
        MIN_EL="$MIN_EL_VAL"
    fi
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/ilrs_laser_ranging_setup_result.json << EOF
{
    "matera_exists": $MATERA_EXISTS,
    "matera_lat": "$(escape_json "$MATERA_LAT")",
    "matera_lon": "$(escape_json "$MATERA_LON")",
    "matera_alt": "$(escape_json "$MATERA_ALT")",
    "yarragadee_exists": $YARRAGADEE_EXISTS,
    "yarragadee_lat": "$(escape_json "$YARRAGADEE_LAT")",
    "yarragadee_lon": "$(escape_json "$YARRAGADEE_LON")",
    "yarragadee_alt": "$(escape_json "$YARRAGADEE_ALT")",
    "ilrs_exists": $ILRS_EXISTS,
    "ilrs_satellites": "$(escape_json "$ILRS_SATELLITES")",
    "ilrs_has_lageos1": $ILRS_HAS_LAGEOS1,
    "ilrs_has_lageos2": $ILRS_HAS_LAGEOS2,
    "ilrs_has_starlette": $ILRS_HAS_STARLETTE,
    "ilrs_has_stella": $ILRS_HAS_STELLA,
    "ilrs_has_lares": $ILRS_HAS_LARES,
    "min_el": "$(escape_json "$MIN_EL")",
    "metric_units_enabled": $METRIC_UNITS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/ilrs_laser_ranging_setup_result.json"
cat /tmp/ilrs_laser_ranging_setup_result.json
echo ""
echo "=== Export Complete ==="