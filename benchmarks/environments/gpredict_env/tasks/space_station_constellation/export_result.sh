#!/bin/bash
# Export script for space_station_constellation task

echo "=== Exporting space_station_constellation result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Read SpaceStations.mod ---
SPACESTATIONS_EXISTS="false"
SPACESTATIONS_SATELLITES=""
SS_HAS_ZARYA="false"     # 25544
SS_HAS_POISK="false"     # 36086
SS_HAS_NAUKA="false"     # 49044
SS_HAS_TIANHE="false"    # 48274
SS_HAS_WENTIAN="false"   # 53239
SS_HAS_MENGTIAN="false"  # 54216

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "space\|station\|iss\|crewed"; then
        SPACESTATIONS_EXISTS="true"
        SPACESTATIONS_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        if echo "$SPACESTATIONS_SATELLITES" | grep -q "25544"; then SS_HAS_ZARYA="true"; fi
        if echo "$SPACESTATIONS_SATELLITES" | grep -q "36086"; then SS_HAS_POISK="true"; fi
        if echo "$SPACESTATIONS_SATELLITES" | grep -q "49044"; then SS_HAS_NAUKA="true"; fi
        if echo "$SPACESTATIONS_SATELLITES" | grep -q "48274"; then SS_HAS_TIANHE="true"; fi
        if echo "$SPACESTATIONS_SATELLITES" | grep -q "53239"; then SS_HAS_WENTIAN="true"; fi
        if echo "$SPACESTATIONS_SATELLITES" | grep -q "54216"; then SS_HAS_MENGTIAN="true"; fi
        break
    fi
done

# --- Read JSC/Houston QTH (lat ~29.5, lon ~-95.1) ---
JSC_EXISTS="false"
JSC_LAT=""
JSC_LON=""
JSC_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "29" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_abs=$(echo "$lon" | sed 's/-//')
        lon_int=$(echo "$lon_abs" | cut -d. -f1)
        if [ "$lon_int" = "95" ]; then
            JSC_EXISTS="true"
            JSC_LAT="$lat"
            JSC_LON="$lon"
            JSC_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Read KSC ground station (lat ~28.5, lon ~-80.6) ---
KSC_EXISTS="false"
KSC_LAT=""
KSC_LON=""
KSC_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "28" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_abs=$(echo "$lon" | sed 's/-//')
        lon_int=$(echo "$lon_abs" | cut -d. -f1)
        if [ "$lon_int" = "80" ]; then
            KSC_EXISTS="true"
            KSC_LAT="$lat"
            KSC_LON="$lon"
            KSC_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Check UTC time setting in gpredict.cfg ---
UTC_TIME_ENABLED="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
GPREDICT_CFG_CONTENT=""

if [ -f "$GPREDICT_CFG" ]; then
    UTC_VAL=$(grep -i "^utc=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UTC_VAL" = "1" ]; then
        UTC_TIME_ENABLED="true"
    fi
    GPREDICT_CFG_CONTENT=$(cat "$GPREDICT_CFG" | tr '\n' '|' | sed 's/"/\\"/g')
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/space_station_constellation_result.json << EOF
{
    "spacestations_exists": $SPACESTATIONS_EXISTS,
    "spacestations_satellites": "$(escape_json "$SPACESTATIONS_SATELLITES")",
    "ss_has_zarya": $SS_HAS_ZARYA,
    "ss_has_poisk": $SS_HAS_POISK,
    "ss_has_nauka": $SS_HAS_NAUKA,
    "ss_has_tianhe": $SS_HAS_TIANHE,
    "ss_has_wentian": $SS_HAS_WENTIAN,
    "ss_has_mengtian": $SS_HAS_MENGTIAN,
    "jsc_exists": $JSC_EXISTS,
    "jsc_lat": "$(escape_json "$JSC_LAT")",
    "jsc_lon": "$(escape_json "$JSC_LON")",
    "jsc_alt": "$(escape_json "$JSC_ALT")",
    "ksc_exists": $KSC_EXISTS,
    "ksc_lat": "$(escape_json "$KSC_LAT")",
    "ksc_lon": "$(escape_json "$KSC_LON")",
    "ksc_alt": "$(escape_json "$KSC_ALT")",
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/space_station_constellation_result.json"
cat /tmp/space_station_constellation_result.json
echo ""
echo "=== Export Complete ==="
