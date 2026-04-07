#!/bin/bash
# Export script for leop_custom_tle_ingestion task

echo "=== Exporting leop_custom_tle_ingestion result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- 1. Check TLE Server logs ---
HTTP_ACCESSED="false"
if [ -f /tmp/tle_server.log ] && grep -qi "GET /techsat.txt" /tmp/tle_server.log; then
    HTTP_ACCESSED="true"
fi

# --- 2. Check GPredict Configuration for TLE URL ---
URL_CONFIGURED="false"
GPREDICT_CFG_CONTENT=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    GPREDICT_CFG_CONTENT=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | tr '\n' '|' | sed 's/"/\\"/g')
    if grep -q "localhost:8080/techsat.txt" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        URL_CONFIGURED="true"
    fi
fi

# --- 3. Check for imported satellite data (47438) ---
SAT_IMPORTED="false"
if [ -f "${GPREDICT_CONF_DIR}/satdata/47438.sat" ] || [ -f "${GPREDICT_CONF_DIR}/satdata/47438.tle" ]; then
    SAT_IMPORTED="true"
fi

# --- 4. Check for Ottawa_Lab ground station ---
OTTAWA_EXISTS="false"
OTTAWA_LAT=""
OTTAWA_LON=""
OTTAWA_ALT=""
OTTAWA_QTH_FILENAME=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "ottawa"; then
        OTTAWA_EXISTS="true"
        OTTAWA_QTH_FILENAME="$(basename "$qth")"
        OTTAWA_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        OTTAWA_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        OTTAWA_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- 5. Check for LEOP_Tracking module ---
LEOP_EXISTS="false"
LEOP_SATELLITES=""
LEOP_QTHFILE=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "leop"; then
        LEOP_EXISTS="true"
        LEOP_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        LEOP_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/leop_custom_tle_ingestion_result.json << EOF
{
    "url_configured": $URL_CONFIGURED,
    "http_accessed": $HTTP_ACCESSED,
    "sat_imported": $SAT_IMPORTED,
    "ottawa_exists": $OTTAWA_EXISTS,
    "ottawa_filename": "$(escape_json "$OTTAWA_QTH_FILENAME")",
    "ottawa_lat": "$(escape_json "$OTTAWA_LAT")",
    "ottawa_lon": "$(escape_json "$OTTAWA_LON")",
    "ottawa_alt": "$(escape_json "$OTTAWA_ALT")",
    "leop_exists": $LEOP_EXISTS,
    "leop_satellites": "$(escape_json "$LEOP_SATELLITES")",
    "leop_qthfile": "$(escape_json "$LEOP_QTHFILE")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/leop_custom_tle_ingestion_result.json"
cat /tmp/leop_custom_tle_ingestion_result.json
echo ""
echo "=== Export Complete ==="