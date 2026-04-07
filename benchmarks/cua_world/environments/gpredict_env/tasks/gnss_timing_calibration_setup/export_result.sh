#!/bin/bash
# Export script for gnss_timing_calibration_setup task

echo "=== Exporting gnss_timing_calibration_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check 1: TLE URL added ---
TLE_URL_ADDED="false"
if grep -qi "gnss\.txt" "${GPREDICT_CONF_DIR}/gpredict.cfg" 2>/dev/null; then
    TLE_URL_ADDED="true"
fi

# --- Check 2: Network Update Executed (did the sat files appear?) ---
TLE_DOWNLOADED="false"
if [ -f "${GPREDICT_CONF_DIR}/satdata/55268.sat" ] || [ -f "${GPREDICT_CONF_DIR}/satdata/48859.sat" ]; then
    TLE_DOWNLOADED="true"
fi

# --- Check 3: NIST_Boulder QTH (scan by coordinates) ---
NIST_EXISTS="false"
NIST_LAT=""
NIST_LON=""
NIST_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    # NIST Boulder is 39.9936 (so starts with 39)
    if [ "$lat_int" = "39" ] || [ "$lat_int" = "40" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_abs=$(echo "$lon" | sed 's/-//')
        lon_int=$(echo "$lon_abs" | cut -d. -f1)
        if [ "$lon_int" = "105" ]; then
            NIST_EXISTS="true"
            NIST_LAT="$lat"
            NIST_LON="$lon"
            NIST_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Check 4: Default QTH ---
DEFAULT_QTH=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# --- Check 5: GNSS_Timing module ---
GNSS_MOD_EXISTS="false"
GNSS_SATELLITES=""
GNSS_HAS_55268="false"
GNSS_HAS_48859="false"
GNSS_HAS_43058="false"
GNSS_HAS_43565="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "gnss\|timing\|nist"; then
        GNSS_MOD_EXISTS="true"
        GNSS_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        if echo "$GNSS_SATELLITES" | grep -q "55268"; then GNSS_HAS_55268="true"; fi
        if echo "$GNSS_SATELLITES" | grep -q "48859"; then GNSS_HAS_48859="true"; fi
        if echo "$GNSS_SATELLITES" | grep -q "43058"; then GNSS_HAS_43058="true"; fi
        if echo "$GNSS_SATELLITES" | grep -q "43565"; then GNSS_HAS_43565="true"; fi
        break
    fi
done

# --- Check 6: UTC Time setting in gpredict.cfg ---
UTC_TIME_ENABLED="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
GPREDICT_CFG_CONTENT=""

if [ -f "$GPREDICT_CFG" ]; then
    GPREDICT_CFG_CONTENT=$(cat "$GPREDICT_CFG" | tr '\n' '|' | sed 's/"/\\"/g')
    # Check for TIME_LOCAL=false (Standard) or utc=1 (Older/Alternative)
    if grep -qi "TIME_LOCAL=false" "$GPREDICT_CFG"; then
        UTC_TIME_ENABLED="true"
    elif grep -qi "utc=1" "$GPREDICT_CFG"; then
        UTC_TIME_ENABLED="true"
    fi
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/gnss_timing_calibration_setup_result.json << EOF
{
    "tle_url_added": $TLE_URL_ADDED,
    "tle_downloaded": $TLE_DOWNLOADED,
    "nist_exists": $NIST_EXISTS,
    "nist_lat": "$(escape_json "$NIST_LAT")",
    "nist_lon": "$(escape_json "$NIST_LON")",
    "nist_alt": "$(escape_json "$NIST_ALT")",
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "gnss_mod_exists": $GNSS_MOD_EXISTS,
    "gnss_satellites": "$(escape_json "$GNSS_SATELLITES")",
    "gnss_has_55268": $GNSS_HAS_55268,
    "gnss_has_48859": $GNSS_HAS_48859,
    "gnss_has_43058": $GNSS_HAS_43058,
    "gnss_has_43565": $GNSS_HAS_43565,
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/gnss_timing_calibration_setup_result.json"
cat /tmp/gnss_timing_calibration_setup_result.json
echo ""
echo "=== Export Complete ==="