#!/bin/bash
# Export script for research_vessel_expedition task

echo "=== Exporting research_vessel_expedition result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Check if PreviousCruise was deleted
PREVIOUS_CRUISE_DELETED="true"
if [ -f "${GPREDICT_CONF_DIR}/PreviousCruise.qth" ]; then
    PREVIOUS_CRUISE_DELETED="false"
fi

# --- Find Woods_Hole QTH by coordinates (~41.5 N, ~-70.6 W) ---
WOODS_HOLE_EXISTS="false"
WOODS_HOLE_QTH_FILE=""
WOODS_HOLE_LAT=""
WOODS_HOLE_LON=""
WOODS_HOLE_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth")
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    
    # Check if lat starts with 41.5
    if echo "$lat" | grep -q "^41\.5"; then
        WOODS_HOLE_EXISTS="true"
        WOODS_HOLE_QTH_FILE="$basename_qth"
        WOODS_HOLE_LAT="$lat"
        WOODS_HOLE_LON="$lon"
        WOODS_HOLE_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Find MidAtlantic QTH by coordinates (~42.0 N, ~-30.0 W) ---
MIDATLANTIC_EXISTS="false"
MIDATLANTIC_QTH_FILE=""
MIDATLANTIC_LAT=""
MIDATLANTIC_LON=""
MIDATLANTIC_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth")
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    
    # Check if lat starts with 42.0 and lon starts with -30.0
    if echo "$lat" | grep -q "^42\.0" && echo "$lon" | grep -q "^-30\.0"; then
        MIDATLANTIC_EXISTS="true"
        MIDATLANTIC_QTH_FILE="$basename_qth"
        MIDATLANTIC_LAT="$lat"
        MIDATLANTIC_LON="$lon"
        MIDATLANTIC_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Read WX_Reception module ---
WX_EXISTS="false"
WX_SATELLITES=""
WX_QTHFILE=""
WX_MTIME="0"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "wx\|weather\|reception"; then
        WX_EXISTS="true"
        WX_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        WX_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        WX_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        break
    fi
done

# --- Read SatComm module ---
SATCOMM_EXISTS="false"
SATCOMM_SATELLITES=""
SATCOMM_QTHFILE=""
SATCOMM_MTIME="0"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "satcomm\|comm"; then
        SATCOMM_EXISTS="true"
        SATCOMM_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        SATCOMM_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        SATCOMM_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        break
    fi
done

# --- Check Amateur module ---
AMATEUR_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_EXISTS="true"
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/research_vessel_expedition_result.json << EOF
{
    "task_start_time": $TASK_START,
    "previous_cruise_deleted": $PREVIOUS_CRUISE_DELETED,
    "woods_hole_exists": $WOODS_HOLE_EXISTS,
    "woods_hole_qth_file": "$(escape_json "$WOODS_HOLE_QTH_FILE")",
    "woods_hole_lat": "$(escape_json "$WOODS_HOLE_LAT")",
    "woods_hole_lon": "$(escape_json "$WOODS_HOLE_LON")",
    "woods_hole_alt": "$(escape_json "$WOODS_HOLE_ALT")",
    "midatlantic_exists": $MIDATLANTIC_EXISTS,
    "midatlantic_qth_file": "$(escape_json "$MIDATLANTIC_QTH_FILE")",
    "midatlantic_lat": "$(escape_json "$MIDATLANTIC_LAT")",
    "midatlantic_lon": "$(escape_json "$MIDATLANTIC_LON")",
    "midatlantic_alt": "$(escape_json "$MIDATLANTIC_ALT")",
    "wx_exists": $WX_EXISTS,
    "wx_mtime": $WX_MTIME,
    "wx_satellites": "$(escape_json "$WX_SATELLITES")",
    "wx_qthfile": "$(escape_json "$WX_QTHFILE")",
    "satcomm_exists": $SATCOMM_EXISTS,
    "satcomm_mtime": $SATCOMM_MTIME,
    "satcomm_satellites": "$(escape_json "$SATCOMM_SATELLITES")",
    "satcomm_qthfile": "$(escape_json "$SATCOMM_QTHFILE")",
    "amateur_exists": $AMATEUR_EXISTS
}
EOF

echo "Result saved to /tmp/research_vessel_expedition_result.json"
cat /tmp/research_vessel_expedition_result.json
echo "=== Export Complete ==="