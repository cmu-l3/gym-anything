#!/bin/bash
# Export script for bistatic_radar_bounce_setup task

echo "=== Exporting bistatic_radar_bounce_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Read Strasbourg QTH (scan by latitude ~48.5) ---
STRASBOURG_EXISTS="false"
STRASBOURG_LAT=""
STRASBOURG_LON=""
STRASBOURG_ALT=""
STRASBOURG_FILENAME=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "48" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | cut -d. -f1)
        if [ "$lon_int" = "7" ]; then
            STRASBOURG_EXISTS="true"
            STRASBOURG_FILENAME="$basename_qth"
            STRASBOURG_LAT="$lat"
            STRASBOURG_LON="$lon"
            STRASBOURG_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Read gpredict.cfg for Global Preferences ---
DEFAULT_QTH=""
MIN_EL="0"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    # Can appear in multiple places or specific sections depending on version, checking globally
    MIN_EL=$(grep -i "^MIN_EL=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# --- Read High_RCS_Targets.mod ---
MOD_EXISTS="false"
MOD_SATELLITES=""
MOD_LAYOUT=""
HAS_ISS="false"      # 25544
HAS_TIANHE="false"   # 48274
HAS_METOP_B="false"  # 38771
HAS_METOP_C="false"  # 43689

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "high\|rcs\|target\|radar"; then
        MOD_EXISTS="true"
        MOD_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        MOD_LAYOUT=$(grep -i "^LAYOUT=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        
        if echo "$MOD_SATELLITES" | grep -q "25544"; then HAS_ISS="true"; fi
        if echo "$MOD_SATELLITES" | grep -q "48274"; then HAS_TIANHE="true"; fi
        if echo "$MOD_SATELLITES" | grep -q "38771"; then HAS_METOP_B="true"; fi
        if echo "$MOD_SATELLITES" | grep -q "43689"; then HAS_METOP_C="true"; fi
        break
    fi
done

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/bistatic_radar_bounce_setup_result.json << EOF
{
    "strasbourg_exists": $STRASBOURG_EXISTS,
    "strasbourg_filename": "$(escape_json "$STRASBOURG_FILENAME")",
    "strasbourg_lat": "$(escape_json "$STRASBOURG_LAT")",
    "strasbourg_lon": "$(escape_json "$STRASBOURG_LON")",
    "strasbourg_alt": "$(escape_json "$STRASBOURG_ALT")",
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "min_el": "$(escape_json "$MIN_EL")",
    "mod_exists": $MOD_EXISTS,
    "mod_satellites": "$(escape_json "$MOD_SATELLITES")",
    "mod_layout": "$(escape_json "$MOD_LAYOUT")",
    "has_iss": $HAS_ISS,
    "has_tianhe": $HAS_TIANHE,
    "has_metop_b": $HAS_METOP_B,
    "has_metop_c": $HAS_METOP_C,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/bistatic_radar_bounce_setup_result.json"
cat /tmp/bistatic_radar_bounce_setup_result.json
echo ""
echo "=== Export Complete ==="