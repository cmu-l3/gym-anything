#!/bin/bash
# Export script for museum_kiosk_display task

echo "=== Exporting museum_kiosk_display result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# --- Check Fullscreen State ---
FULLSCREEN="false"
WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l | grep -i "Gpredict" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xprop -id $WID _NET_WM_STATE 2>/dev/null | grep -qi "FULLSCREEN"; then
        FULLSCREEN="true"
    fi
    # Fallback: check geometry
    GEOM=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l -G | grep -i "Gpredict" | head -1)
    W=$(echo "$GEOM" | awk '{print $5}')
    H=$(echo "$GEOM" | awk '{print $6}')
    if [ "$W" = "1920" ] && [ "$H" = "1080" ]; then 
        FULLSCREEN="true"
    fi
fi

# --- Find and parse MSI_Chicago.qth ---
MSI_EXISTS="false"
MSI_LAT=""
MSI_LON=""
MSI_ALT=""
MSI_MTIME="0"

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # Check by filename or approximate latitude
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    
    if echo "$basename_qth" | grep -qi "msi\|chicago" || [ "$lat_int" = "41" ]; then
        MSI_EXISTS="true"
        MSI_LAT="$lat"
        MSI_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        MSI_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        MSI_MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
        break
    fi
done

# --- Find and parse Crewed_Missions.mod ---
CREWED_EXISTS="false"
CREWED_SATELLITES=""
CREWED_QTHFILE=""
CREWED_MTIME="0"
CREWED_SHOWMAP="0"
CREWED_SHOWEV="0"
CREWED_SHOWPOLARPLOT="0"
CREWED_SHOWSKYAT="0"
CREWED_LAYOUT="-1"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    
    if echo "$modname" | grep -qi "crew\|mission"; then
        CREWED_EXISTS="true"
        CREWED_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        CREWED_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r\n')
        CREWED_SHOWMAP=$(grep -i "^SHOWMAP=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        CREWED_SHOWEV=$(grep -i "^SHOWEV=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        CREWED_SHOWPOLARPLOT=$(grep -i "^SHOWPOLARPLOT=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        CREWED_SHOWSKYAT=$(grep -i "^SHOWSKYAT=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        CREWED_LAYOUT=$(grep -i "^LAYOUT=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        CREWED_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        break
    fi
done

# --- Parse gpredict.cfg for UI/Tracks ---
CFG_FILE="${GPREDICT_CONF_DIR}/gpredict.cfg"
GUI_MODULES=""
CFG_CONTENT=""

if [ -f "$CFG_FILE" ]; then
    GUI_MODULES=$(grep -i "^modules=" "$CFG_FILE" | head -1 | cut -d= -f2 | tr -d '\r\n')
    # Capture relevant mapping/track settings safely without line breaks breaking JSON
    CFG_CONTENT=$(cat "$CFG_FILE" | tr '\n' '|' | sed 's/"/\\"/g')
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "fullscreen_active": $FULLSCREEN,
    "msi_exists": $MSI_EXISTS,
    "msi_lat": "$(escape_json "$MSI_LAT")",
    "msi_lon": "$(escape_json "$MSI_LON")",
    "msi_alt": "$(escape_json "$MSI_ALT")",
    "msi_mtime": $MSI_MTIME,
    "crewed_exists": $CREWED_EXISTS,
    "crewed_satellites": "$(escape_json "$CREWED_SATELLITES")",
    "crewed_qthfile": "$(escape_json "$CREWED_QTHFILE")",
    "crewed_showmap": "$(escape_json "$CREWED_SHOWMAP")",
    "crewed_showev": "$(escape_json "$CREWED_SHOWEV")",
    "crewed_showpolarplot": "$(escape_json "$CREWED_SHOWPOLARPLOT")",
    "crewed_showskyat": "$(escape_json "$CREWED_SHOWSKYAT")",
    "crewed_layout": "$(escape_json "$CREWED_LAYOUT")",
    "crewed_mtime": $CREWED_MTIME,
    "gui_modules": "$(escape_json "$GUI_MODULES")",
    "cfg_content": "$(escape_json "$CFG_CONTENT")",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="