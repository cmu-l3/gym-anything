#!/bin/bash
# Export script for amateur_module_reorganization task

echo "=== Exporting amateur_module_reorganization result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Read Linear.mod ---
LINEAR_EXISTS="false"
LINEAR_SATELLITES=""
LINEAR_HAS_AO7="false"
LINEAR_HAS_FO29="false"
LINEAR_HAS_AO73="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "linear\|lin\b"; then
        LINEAR_EXISTS="true"
        LINEAR_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        # AO-7 NORAD is 7530 (stored without leading zero)
        if echo "$LINEAR_SATELLITES" | grep -qE "7530|07530"; then LINEAR_HAS_AO7="true"; fi
        if echo "$LINEAR_SATELLITES" | grep -q "24278"; then LINEAR_HAS_FO29="true"; fi
        if echo "$LINEAR_SATELLITES" | grep -q "39444"; then LINEAR_HAS_AO73="true"; fi
        break
    fi
done

# --- Read FM_Voice.mod ---
FMVOICE_EXISTS="false"
FMVOICE_SATELLITES=""
FMVOICE_HAS_AO27="false"
FMVOICE_HAS_SO50="false"
FMVOICE_HAS_AO85="false"
FMVOICE_HAS_AO95="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "fm\|voice\|fm_voice\|fmvoice"; then
        FMVOICE_EXISTS="true"
        FMVOICE_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        if echo "$FMVOICE_SATELLITES" | grep -q "22825"; then FMVOICE_HAS_AO27="true"; fi
        if echo "$FMVOICE_SATELLITES" | grep -q "27607"; then FMVOICE_HAS_SO50="true"; fi
        if echo "$FMVOICE_SATELLITES" | grep -q "40967"; then FMVOICE_HAS_AO85="true"; fi
        if echo "$FMVOICE_SATELLITES" | grep -q "43770"; then FMVOICE_HAS_AO95="true"; fi
        break
    fi
done

# --- Read Remote_RX.qth (scan by latitude ~40.7 and longitude ~-74.0) ---
REMOTE_RX_EXISTS="false"
REMOTE_RX_LAT=""
REMOTE_RX_LON=""
REMOTE_RX_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    # Skip Pittsburgh (already known)
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "40" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_abs=$(echo "$lon" | sed 's/-//')
        lon_int=$(echo "$lon_abs" | cut -d. -f1)
        # Remote_RX is near NYC area (~74W longitude)
        if [ "$lon_int" = "74" ]; then
            REMOTE_RX_EXISTS="true"
            REMOTE_RX_LAT="$lat"
            REMOTE_RX_LON="$lon"
            REMOTE_RX_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/amateur_module_reorganization_result.json << EOF
{
    "linear_exists": $LINEAR_EXISTS,
    "linear_satellites": "$(escape_json "$LINEAR_SATELLITES")",
    "linear_has_ao7": $LINEAR_HAS_AO7,
    "linear_has_fo29": $LINEAR_HAS_FO29,
    "linear_has_ao73": $LINEAR_HAS_AO73,
    "fmvoice_exists": $FMVOICE_EXISTS,
    "fmvoice_satellites": "$(escape_json "$FMVOICE_SATELLITES")",
    "fmvoice_has_ao27": $FMVOICE_HAS_AO27,
    "fmvoice_has_so50": $FMVOICE_HAS_SO50,
    "fmvoice_has_ao85": $FMVOICE_HAS_AO85,
    "fmvoice_has_ao95": $FMVOICE_HAS_AO95,
    "remote_rx_exists": $REMOTE_RX_EXISTS,
    "remote_rx_lat": "$(escape_json "$REMOTE_RX_LAT")",
    "remote_rx_lon": "$(escape_json "$REMOTE_RX_LON")",
    "remote_rx_alt": "$(escape_json "$REMOTE_RX_ALT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/amateur_module_reorganization_result.json"
cat /tmp/amateur_module_reorganization_result.json
echo ""
echo "=== Export Complete ==="
