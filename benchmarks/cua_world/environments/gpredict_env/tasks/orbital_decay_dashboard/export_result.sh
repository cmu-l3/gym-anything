#!/bin/bash
# Export script for orbital_decay_dashboard task

echo "=== Exporting orbital_decay_dashboard result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# --- Read Vandenberg_SCC.qth ---
VBG_EXISTS="false"
VBG_LAT=""
VBG_LON=""
VBG_ALT=""
VBG_QTH_FILENAME=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # Check if name contains vbg or vandenberg OR coordinates match approximately
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    
    if [ "$lat_int" = "34" ] || echo "$basename_qth" | grep -qi "vandenberg\|vbg"; then
        VBG_EXISTS="true"
        VBG_QTH_FILENAME=$(basename "$qth")
        VBG_LAT="$lat"
        VBG_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        VBG_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Read Decay_Monitor.mod ---
DECAY_MOD_EXISTS="false"
DECAY_SATELLITES=""
DECAY_HAS_ISS="false"      # 25544
DECAY_HAS_TIANHE="false"   # 48274
DECAY_HAS_SUOMI="false"    # 37849
DECAY_QTHFILE=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    
    if echo "$modname" | grep -qi "decay\|monitor"; then
        DECAY_MOD_EXISTS="true"
        DECAY_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        DECAY_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        
        if echo "$DECAY_SATELLITES" | grep -q "25544"; then DECAY_HAS_ISS="true"; fi
        if echo "$DECAY_SATELLITES" | grep -q "48274"; then DECAY_HAS_TIANHE="true"; fi
        if echo "$DECAY_SATELLITES" | grep -q "37849"; then DECAY_HAS_SUOMI="true"; fi
        break
    fi
done

# Application running check
APP_RUNNING=$(pgrep -f "gpredict" > /dev/null && echo "true" || echo "false")

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "vbg_exists": $VBG_EXISTS,
    "vbg_qth_filename": "$(escape_json "$VBG_QTH_FILENAME")",
    "vbg_lat": "$(escape_json "$VBG_LAT")",
    "vbg_lon": "$(escape_json "$VBG_LON")",
    "vbg_alt": "$(escape_json "$VBG_ALT")",
    "decay_mod_exists": $DECAY_MOD_EXISTS,
    "decay_satellites": "$(escape_json "$DECAY_SATELLITES")",
    "decay_has_iss": $DECAY_HAS_ISS,
    "decay_has_tianhe": $DECAY_HAS_TIANHE,
    "decay_has_suomi": $DECAY_HAS_SUOMI,
    "decay_qthfile": "$(escape_json "$DECAY_QTHFILE")",
    "app_running": $APP_RUNNING,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy into standard output location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="