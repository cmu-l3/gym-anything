#!/bin/bash
echo "=== Exporting wildlife_argos_custom_map result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# --- Check 1: Maps directory and files ---
MAP_DIR_EXISTS="false"
MAP_PNG_EXISTS="false"
MAP_INFO_EXISTS="false"

if [ -d "${GPREDICT_CONF_DIR}/maps" ]; then
    MAP_DIR_EXISTS="true"
    if [ -f "${GPREDICT_CONF_DIR}/maps/ocean_bathymetry.png" ]; then
        MAP_PNG_EXISTS="true"
    fi
    if [ -f "${GPREDICT_CONF_DIR}/maps/ocean_bathymetry.info" ]; then
        MAP_INFO_EXISTS="true"
    fi
fi

# --- Check 2: Configuration settings (MAP and Grid) ---
MAP_SETTING=""
GRID_SETTING=""
DEFAULT_QTH_SETTING=""
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    MAP_SETTING=$(grep -i "^MAP=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '\r\n')
    GRID_SETTING=$(grep -i "^DRAW_GRID=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')
    DEFAULT_QTH_SETTING=$(grep -i "^DEFAULT_QTH=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '\r\n')
fi

# --- Check 3: Galapagos Ground Station ---
GALAPAGOS_QTH=""
GALAPAGOS_LAT=""
GALAPAGOS_LON=""
GALAPAGOS_ALT=""
GALAPAGOS_EXISTS="false"

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "galapagos"; then
        GALAPAGOS_EXISTS="true"
        GALAPAGOS_QTH="$basename_qth"
        GALAPAGOS_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        GALAPAGOS_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        GALAPAGOS_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Check 4: Argos Tracking Module ---
ARGOS_EXISTS="false"
ARGOS_SATELLITES=""
ARGOS_MTIME="0"

for mod in "${GPREDICT_CONF_DIR}/modules"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "argos"; then
        ARGOS_EXISTS="true"
        ARGOS_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r\n')
        ARGOS_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        break
    fi
done

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# Create JSON output
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "map_dir_exists": $MAP_DIR_EXISTS,
    "map_png_exists": $MAP_PNG_EXISTS,
    "map_info_exists": $MAP_INFO_EXISTS,
    "map_setting": "$(escape_json "$MAP_SETTING")",
    "grid_setting": "$(escape_json "$GRID_SETTING")",
    "default_qth": "$(escape_json "$DEFAULT_QTH_SETTING")",
    "galapagos_exists": $GALAPAGOS_EXISTS,
    "galapagos_lat": "$(escape_json "$GALAPAGOS_LAT")",
    "galapagos_lon": "$(escape_json "$GALAPAGOS_LON")",
    "galapagos_alt": "$(escape_json "$GALAPAGOS_ALT")",
    "argos_exists": $ARGOS_EXISTS,
    "argos_satellites": "$(escape_json "$ARGOS_SATELLITES")",
    "argos_mtime": $ARGOS_MTIME
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete, JSON written to /tmp/task_result.json."
cat /tmp/task_result.json