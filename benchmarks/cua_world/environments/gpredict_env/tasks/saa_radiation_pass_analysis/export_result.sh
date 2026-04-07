#!/bin/bash
# Export script for saa_radiation_pass_analysis task

echo "=== Exporting saa_radiation_pass_analysis result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Find Tristan_da_Cunha QTH (scan by coords: lat ~ -37.1, lon ~ -12.2) ---
TRISTAN_EXISTS="false"
TRISTAN_QTH_FILENAME=""
TRISTAN_LAT=""
TRISTAN_LON=""
TRISTAN_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1) # Should be -37
    
    if [ "$lat_int" = "-37" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | cut -d. -f1) # Should be -12
        if [ "$lon_int" = "-12" ]; then
            TRISTAN_EXISTS="true"
            TRISTAN_QTH_FILENAME=$(basename "$qth")
            TRISTAN_LAT="$lat"
            TRISTAN_LON="$lon"
            TRISTAN_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Find SAA_Targets module ---
SAA_EXISTS="false"
SAA_MOD_NAME=""
SAA_SATELLITES=""
SAA_QTH_BINDING=""
SAA_HAS_METOPB="false"  # 38771
SAA_HAS_METOPC="false"  # 43689
SAA_HAS_SUOMI="false"   # 37849
SAA_HAS_NOAA19="false"  # 33591

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "saa"; then
        SAA_EXISTS="true"
        SAA_MOD_NAME="$modname"
        SAA_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        SAA_QTH_BINDING=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        
        if echo "$SAA_SATELLITES" | grep -q "38771"; then SAA_HAS_METOPB="true"; fi
        if echo "$SAA_SATELLITES" | grep -q "43689"; then SAA_HAS_METOPC="true"; fi
        if echo "$SAA_SATELLITES" | grep -q "37849"; then SAA_HAS_SUOMI="true"; fi
        if echo "$SAA_SATELLITES" | grep -q "33591"; then SAA_HAS_NOAA19="true"; fi
        break
    fi
done

# --- Check Preferences in gpredict.cfg ---
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
PRED_PASSES="10"
MAP_DRAW_GRID="false"
MAP_DRAW_TERM="false"

if [ -f "$GPREDICT_CFG" ]; then
    # Predict passes
    val_passes=$(grep -i "^PRED_PASSES=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ -n "$val_passes" ]; then PRED_PASSES="$val_passes"; fi
    
    # Map Grid
    val_grid=$(grep -i "^MAP_DRAW_GRID=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$val_grid" = "1" ] || [ "$val_grid" = "true" ] || [ "$val_grid" = "True" ]; then
        MAP_DRAW_GRID="true"
    fi
    
    # Map Terminator
    val_term=$(grep -i "^MAP_DRAW_TERM=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$val_term" = "1" ] || [ "$val_term" = "true" ] || [ "$val_term" = "True" ]; then
        MAP_DRAW_TERM="true"
    fi
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/saa_radiation_pass_analysis_result.json << EOF
{
    "tristan_exists": $TRISTAN_EXISTS,
    "tristan_qth_filename": "$(escape_json "$TRISTAN_QTH_FILENAME")",
    "tristan_lat": "$(escape_json "$TRISTAN_LAT")",
    "tristan_lon": "$(escape_json "$TRISTAN_LON")",
    "tristan_alt": "$(escape_json "$TRISTAN_ALT")",
    "saa_exists": $SAA_EXISTS,
    "saa_mod_name": "$(escape_json "$SAA_MOD_NAME")",
    "saa_satellites": "$(escape_json "$SAA_SATELLITES")",
    "saa_qth_binding": "$(escape_json "$SAA_QTH_BINDING")",
    "saa_has_metopb": $SAA_HAS_METOPB,
    "saa_has_metopc": $SAA_HAS_METOPC,
    "saa_has_suomi": $SAA_HAS_SUOMI,
    "saa_has_noaa19": $SAA_HAS_NOAA19,
    "pred_passes": "$PRED_PASSES",
    "map_draw_grid": $MAP_DRAW_GRID,
    "map_draw_term": $MAP_DRAW_TERM,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/saa_radiation_pass_analysis_result.json"
cat /tmp/saa_radiation_pass_analysis_result.json
echo ""
echo "=== Export Complete ==="