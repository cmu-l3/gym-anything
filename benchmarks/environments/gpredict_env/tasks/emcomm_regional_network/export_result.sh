#!/bin/bash
# Export script for emcomm_regional_network task
# Reads QTH and module files, outputs JSON for verifier

echo "=== Exporting emcomm_regional_network result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Read Pittsburgh.qth ---
PITTSBURGH_QTH="${GPREDICT_CONF_DIR}/Pittsburgh.qth"
PITTSBURGH_LAT=""
PITTSBURGH_LON=""
PITTSBURGH_ALT=""
PITTSBURGH_WX=""
PITTSBURGH_EXISTS="false"

if [ -f "$PITTSBURGH_QTH" ]; then
    PITTSBURGH_EXISTS="true"
    PITTSBURGH_LAT=$(grep -i "^LAT=" "$PITTSBURGH_QTH" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    PITTSBURGH_LON=$(grep -i "^LON=" "$PITTSBURGH_QTH" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    PITTSBURGH_ALT=$(grep -i "^ALT=" "$PITTSBURGH_QTH" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    PITTSBURGH_WX=$(grep -i "^WX=" "$PITTSBURGH_QTH" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# --- Read Erie.qth (may have different capitalization) ---
ERIE_QTH=""
ERIE_LAT=""
ERIE_LON=""
ERIE_ALT=""
ERIE_WX=""
ERIE_EXISTS="false"

# Search for any QTH file with Erie-like coordinates
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    # Check if latitude is approximately 42.1 (Erie PA)
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "42" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | sed 's/-//' | cut -d. -f1)
        if [ "$lon_int" = "80" ]; then
            ERIE_EXISTS="true"
            ERIE_QTH="$basename_qth"
            ERIE_LAT="$lat"
            ERIE_LON="$lon"
            ERIE_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            ERIE_WX=$(grep -i "^WX=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Read Harrisburg.qth ---
HARRISBURG_QTH=""
HARRISBURG_LAT=""
HARRISBURG_LON=""
HARRISBURG_ALT=""
HARRISBURG_WX=""
HARRISBURG_EXISTS="false"

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "40" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        # Harrisburg LON is around -76.89
        lon_abs=$(echo "$lon" | sed 's/-//')
        lon_int=$(echo "$lon_abs" | cut -d. -f1)
        if [ "$lon_int" = "76" ]; then
            HARRISBURG_EXISTS="true"
            HARRISBURG_QTH="$basename_qth"
            HARRISBURG_LAT="$lat"
            HARRISBURG_LON="$lon"
            HARRISBURG_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            HARRISBURG_WX=$(grep -i "^WX=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Read RACES.mod ---
RACES_MOD=""
RACES_EXISTS="false"
RACES_HAS_ISS="false"
RACES_HAS_SO50="false"
RACES_HAS_AO85="false"
RACES_SATELLITES=""

# Search for RACES module (may be named differently)
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "race"; then
        RACES_EXISTS="true"
        RACES_MOD="$modname"
        RACES_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        # Check for required satellite IDs
        if echo "$RACES_SATELLITES" | grep -q "25544"; then
            RACES_HAS_ISS="true"
        fi
        if echo "$RACES_SATELLITES" | grep -q "27607"; then
            RACES_HAS_SO50="true"
        fi
        if echo "$RACES_SATELLITES" | grep -q "40967"; then
            RACES_HAS_AO85="true"
        fi
        break
    fi
done

# Escape strings for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

PITTSBURGH_LAT_ESC=$(escape_json "$PITTSBURGH_LAT")
PITTSBURGH_LON_ESC=$(escape_json "$PITTSBURGH_LON")
PITTSBURGH_ALT_ESC=$(escape_json "$PITTSBURGH_ALT")
PITTSBURGH_WX_ESC=$(escape_json "$PITTSBURGH_WX")
ERIE_LAT_ESC=$(escape_json "$ERIE_LAT")
ERIE_LON_ESC=$(escape_json "$ERIE_LON")
ERIE_ALT_ESC=$(escape_json "$ERIE_ALT")
HARRISBURG_LAT_ESC=$(escape_json "$HARRISBURG_LAT")
HARRISBURG_LON_ESC=$(escape_json "$HARRISBURG_LON")
HARRISBURG_ALT_ESC=$(escape_json "$HARRISBURG_ALT")
RACES_SAT_ESC=$(escape_json "$RACES_SATELLITES")

cat > /tmp/emcomm_regional_network_result.json << EOF
{
    "pittsburgh_exists": $PITTSBURGH_EXISTS,
    "pittsburgh_lat": "$PITTSBURGH_LAT_ESC",
    "pittsburgh_lon": "$PITTSBURGH_LON_ESC",
    "pittsburgh_alt": "$PITTSBURGH_ALT_ESC",
    "pittsburgh_wx": "$PITTSBURGH_WX_ESC",
    "erie_exists": $ERIE_EXISTS,
    "erie_lat": "$ERIE_LAT_ESC",
    "erie_lon": "$ERIE_LON_ESC",
    "erie_alt": "$ERIE_ALT_ESC",
    "harrisburg_exists": $HARRISBURG_EXISTS,
    "harrisburg_lat": "$HARRISBURG_LAT_ESC",
    "harrisburg_lon": "$HARRISBURG_LON_ESC",
    "harrisburg_alt": "$HARRISBURG_ALT_ESC",
    "races_exists": $RACES_EXISTS,
    "races_mod_name": "$(escape_json "$RACES_MOD")",
    "races_satellites": "$RACES_SAT_ESC",
    "races_has_iss": $RACES_HAS_ISS,
    "races_has_so50": $RACES_HAS_SO50,
    "races_has_ao85": $RACES_HAS_AO85,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/emcomm_regional_network_result.json"
cat /tmp/emcomm_regional_network_result.json
echo ""
echo "=== Export Complete ==="
