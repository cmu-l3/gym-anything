#!/bin/bash
# Export script for classify_and_reorganize_satellites task

echo "=== Exporting classify_and_reorganize_satellites result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Read Amateur.mod current state ---
AMATEUR_EXISTS="false"
AMATEUR_SATELLITES=""
AMATEUR_STILL_HAS_SUOMI="false"    # 37849
AMATEUR_STILL_HAS_FY3A="false"     # 32958
AMATEUR_STILL_HAS_FY3B="false"     # 37214
AMATEUR_STILL_HAS_DMSP="false"     # 35951

AMATEUR_MOD="${GPREDICT_MOD_DIR}/Amateur.mod"
if [ -f "$AMATEUR_MOD" ]; then
    AMATEUR_EXISTS="true"
    AMATEUR_SATELLITES=$(grep -i "^SATELLITES=" "$AMATEUR_MOD" | head -1 | cut -d= -f2)
    if echo "$AMATEUR_SATELLITES" | grep -q "37849"; then AMATEUR_STILL_HAS_SUOMI="true"; fi
    if echo "$AMATEUR_SATELLITES" | grep -q "32958"; then AMATEUR_STILL_HAS_FY3A="true"; fi
    if echo "$AMATEUR_SATELLITES" | grep -q "37214"; then AMATEUR_STILL_HAS_FY3B="true"; fi
    if echo "$AMATEUR_SATELLITES" | grep -q "35951"; then AMATEUR_STILL_HAS_DMSP="true"; fi
fi

# --- Read WeatherSats.mod (search for any module with "weather" in name) ---
WEATHERSATS_EXISTS="false"
WEATHERSATS_SATELLITES=""
WS_HAS_SUOMI="false"    # 37849
WS_HAS_FY3A="false"     # 32958
WS_HAS_FY3B="false"     # 37214
WS_HAS_DMSP="false"     # 35951
WEATHERSATS_MOD_NAME=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    # Skip Amateur module
    if echo "$modname" | grep -qi "^amateur$"; then continue; fi
    if echo "$modname" | grep -qi "weather\|wx\|meteo"; then
        WEATHERSATS_EXISTS="true"
        WEATHERSATS_MOD_NAME="$modname"
        WEATHERSATS_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        if echo "$WEATHERSATS_SATELLITES" | grep -q "37849"; then WS_HAS_SUOMI="true"; fi
        if echo "$WEATHERSATS_SATELLITES" | grep -q "32958"; then WS_HAS_FY3A="true"; fi
        if echo "$WEATHERSATS_SATELLITES" | grep -q "37214"; then WS_HAS_FY3B="true"; fi
        if echo "$WEATHERSATS_SATELLITES" | grep -q "35951"; then WS_HAS_DMSP="true"; fi
        break
    fi
done

# --- Read Fairbanks QTH (lat ~64.8) ---
FAIRBANKS_EXISTS="false"
FAIRBANKS_LAT=""
FAIRBANKS_LON=""
FAIRBANKS_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

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

# --- Check metric units ---
METRIC_UNITS="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
GPREDICT_CFG_CONTENT=""

if [ -f "$GPREDICT_CFG" ]; then
    UNIT_VAL=$(grep -i "^unit=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UNIT_VAL" = "0" ]; then
        METRIC_UNITS="true"
    fi
    GPREDICT_CFG_CONTENT=$(cat "$GPREDICT_CFG" | tr '\n' '|' | sed 's/"/\\"/g')
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/classify_and_reorganize_satellites_result.json << EOF
{
    "amateur_exists": $AMATEUR_EXISTS,
    "amateur_satellites": "$(escape_json "$AMATEUR_SATELLITES")",
    "amateur_still_has_suomi": $AMATEUR_STILL_HAS_SUOMI,
    "amateur_still_has_fy3a": $AMATEUR_STILL_HAS_FY3A,
    "amateur_still_has_fy3b": $AMATEUR_STILL_HAS_FY3B,
    "amateur_still_has_dmsp": $AMATEUR_STILL_HAS_DMSP,
    "weathersats_exists": $WEATHERSATS_EXISTS,
    "weathersats_mod_name": "$(escape_json "$WEATHERSATS_MOD_NAME")",
    "weathersats_satellites": "$(escape_json "$WEATHERSATS_SATELLITES")",
    "ws_has_suomi": $WS_HAS_SUOMI,
    "ws_has_fy3a": $WS_HAS_FY3A,
    "ws_has_fy3b": $WS_HAS_FY3B,
    "ws_has_dmsp": $WS_HAS_DMSP,
    "fairbanks_exists": $FAIRBANKS_EXISTS,
    "fairbanks_lat": "$(escape_json "$FAIRBANKS_LAT")",
    "fairbanks_lon": "$(escape_json "$FAIRBANKS_LON")",
    "fairbanks_alt": "$(escape_json "$FAIRBANKS_ALT")",
    "metric_units_enabled": $METRIC_UNITS,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/classify_and_reorganize_satellites_result.json"
cat /tmp/classify_and_reorganize_satellites_result.json
echo ""
echo "=== Export Complete ==="
