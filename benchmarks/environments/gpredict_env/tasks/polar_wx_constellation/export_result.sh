#!/bin/bash
# Export script for polar_wx_constellation task

echo "=== Exporting polar_wx_constellation result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Read PolarWX.mod ---
POLARWX_EXISTS="false"
POLARWX_SATELLITES=""
POLARWX_HAS_SUOMI_NPP="false"
POLARWX_HAS_FY3A="false"
POLARWX_HAS_FY3B="false"
POLARWX_HAS_DMSP_F18="false"
POLARWX_HAS_ISS="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "polar\|polwx\|polarwx\|weather"; then
        POLARWX_EXISTS="true"
        POLARWX_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        if echo "$POLARWX_SATELLITES" | grep -q "37849"; then POLARWX_HAS_SUOMI_NPP="true"; fi
        if echo "$POLARWX_SATELLITES" | grep -q "32958"; then POLARWX_HAS_FY3A="true"; fi
        if echo "$POLARWX_SATELLITES" | grep -q "37214"; then POLARWX_HAS_FY3B="true"; fi
        if echo "$POLARWX_SATELLITES" | grep -q "35951"; then POLARWX_HAS_DMSP_F18="true"; fi
        if echo "$POLARWX_SATELLITES" | grep -q "25544"; then POLARWX_HAS_ISS="true"; fi
        break
    fi
done

# --- Read Fairbanks QTH (scan by latitude ~64.8) ---
FAIRBANKS_EXISTS="false"
FAIRBANKS_LAT=""
FAIRBANKS_LON=""
FAIRBANKS_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "64" ]; then
        FAIRBANKS_EXISTS="true"
        FAIRBANKS_LAT="$lat"
        FAIRBANKS_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        FAIRBANKS_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Read Anchorage QTH (scan by latitude ~61.2) ---
ANCHORAGE_EXISTS="false"
ANCHORAGE_LAT=""
ANCHORAGE_LON=""
ANCHORAGE_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "61" ]; then
        ANCHORAGE_EXISTS="true"
        ANCHORAGE_LAT="$lat"
        ANCHORAGE_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        ANCHORAGE_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Read gpredict.cfg for metric units ---
METRIC_UNITS="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    # GPredict stores unit in [misc] section as unit=0 (km/metric) or unit=1 (miles)
    UNIT_VAL=$(grep -i "^unit=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UNIT_VAL" = "0" ]; then
        METRIC_UNITS="true"
    fi
fi

# Capture full gpredict.cfg for flexible verification
GPREDICT_CFG_CONTENT=""
if [ -f "$GPREDICT_CFG" ]; then
    GPREDICT_CFG_CONTENT=$(cat "$GPREDICT_CFG" | tr '\n' '|' | sed 's/"/\\"/g')
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/polar_wx_constellation_result.json << EOF
{
    "polarwx_exists": $POLARWX_EXISTS,
    "polarwx_satellites": "$(escape_json "$POLARWX_SATELLITES")",
    "polarwx_has_suomi_npp": $POLARWX_HAS_SUOMI_NPP,
    "polarwx_has_fy3a": $POLARWX_HAS_FY3A,
    "polarwx_has_fy3b": $POLARWX_HAS_FY3B,
    "polarwx_has_dmsp_f18": $POLARWX_HAS_DMSP_F18,
    "polarwx_has_iss": $POLARWX_HAS_ISS,
    "fairbanks_exists": $FAIRBANKS_EXISTS,
    "fairbanks_lat": "$(escape_json "$FAIRBANKS_LAT")",
    "fairbanks_lon": "$(escape_json "$FAIRBANKS_LON")",
    "fairbanks_alt": "$(escape_json "$FAIRBANKS_ALT")",
    "anchorage_exists": $ANCHORAGE_EXISTS,
    "anchorage_lat": "$(escape_json "$ANCHORAGE_LAT")",
    "anchorage_lon": "$(escape_json "$ANCHORAGE_LON")",
    "anchorage_alt": "$(escape_json "$ANCHORAGE_ALT")",
    "metric_units_enabled": $METRIC_UNITS,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/polar_wx_constellation_result.json"
cat /tmp/polar_wx_constellation_result.json
echo ""
echo "=== Export Complete ==="
