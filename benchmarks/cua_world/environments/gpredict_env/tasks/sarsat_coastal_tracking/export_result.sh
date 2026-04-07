#!/bin/bash
echo "=== Exporting sarsat_coastal_tracking result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Check if obsolete modules still exist
TESTSATS_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/TestSats.mod" ]; then TESTSATS_EXISTS="true"; fi

OLDWEATHER_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/OldWeather.mod" ]; then OLDWEATHER_EXISTS="true"; fi

# Check if Amateur module was correctly preserved
AMATEUR_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then AMATEUR_EXISTS="true"; fi

# Look for SARSAT module
SARSAT_EXISTS="false"
SARSAT_SATELLITES=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "sarsat"; then
        SARSAT_EXISTS="true"
        SARSAT_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        break
    fi
done

# Scan QTH files for Boston and Cape May ground stations
BOSTON_EXISTS="false"
BOSTON_FILE=""
BOSTON_LAT=""
BOSTON_LON=""
BOSTON_ALT=""

CAPEMAY_EXISTS="false"
CAPEMAY_FILE=""
CAPEMAY_LAT=""
CAPEMAY_LON=""
CAPEMAY_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth")
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    alt=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    
    lat_int=$(echo "$lat" | cut -d. -f1)
    
    # Check Boston (lat ~42.3, lon ~-71.0)
    if [ "$lat_int" = "42" ]; then
        lon_int=$(echo "$lon" | sed 's/-//' | cut -d. -f1)
        if [ "$lon_int" = "71" ]; then
            BOSTON_EXISTS="true"
            BOSTON_FILE="$basename_qth"
            BOSTON_LAT="$lat"
            BOSTON_LON="$lon"
            BOSTON_ALT="$alt"
        fi
    fi
    
    # Check Cape May (lat ~38.9, lon ~-74.9)
    if [ "$lat_int" = "38" ]; then
        lon_int=$(echo "$lon" | sed 's/-//' | cut -d. -f1)
        if [ "$lon_int" = "74" ]; then
            CAPEMAY_EXISTS="true"
            CAPEMAY_FILE="$basename_qth"
            CAPEMAY_LAT="$lat"
            CAPEMAY_LON="$lon"
            CAPEMAY_ALT="$alt"
        fi
    fi
done

# Read default QTH
DEFAULT_QTH=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# Utility to escape strings for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# Compile output JSON
cat > /tmp/sarsat_coastal_tracking_result.json << EOF
{
    "testsats_exists": $TESTSATS_EXISTS,
    "oldweather_exists": $OLDWEATHER_EXISTS,
    "amateur_exists": $AMATEUR_EXISTS,
    "sarsat_exists": $SARSAT_EXISTS,
    "sarsat_satellites": "$(escape_json "$SARSAT_SATELLITES")",
    "boston_exists": $BOSTON_EXISTS,
    "boston_file": "$(escape_json "$BOSTON_FILE")",
    "boston_lat": "$(escape_json "$BOSTON_LAT")",
    "boston_lon": "$(escape_json "$BOSTON_LON")",
    "boston_alt": "$(escape_json "$BOSTON_ALT")",
    "capemay_exists": $CAPEMAY_EXISTS,
    "capemay_file": "$(escape_json "$CAPEMAY_FILE")",
    "capemay_lat": "$(escape_json "$CAPEMAY_LAT")",
    "capemay_lon": "$(escape_json "$CAPEMAY_LON")",
    "capemay_alt": "$(escape_json "$CAPEMAY_ALT")",
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/sarsat_coastal_tracking_result.json"
cat /tmp/sarsat_coastal_tracking_result.json
echo ""
echo "=== Export Complete ==="