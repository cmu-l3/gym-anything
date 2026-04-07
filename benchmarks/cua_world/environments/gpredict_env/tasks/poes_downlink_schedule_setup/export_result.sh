#!/bin/bash
# Export script for poes_downlink_schedule_setup task
# Reads GPredict config files and pass export file, outputs JSON for verifier

echo "=== Exporting poes_downlink_schedule_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_FILE="/tmp/poes_downlink_schedule_setup_result.json"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# ---------------------------------------------------------------
# 1. Read Wallops_CDA.qth
# ---------------------------------------------------------------
WALLOPS_EXISTS="false"
WALLOPS_LAT=""
WALLOPS_LON=""
WALLOPS_ALT=""
WALLOPS_WX=""

# Search for any QTH with "wallops" in the name
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "wallops"; then
        WALLOPS_EXISTS="true"
        WALLOPS_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        WALLOPS_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        WALLOPS_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        WALLOPS_WX=$(grep -i "^WX=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# ---------------------------------------------------------------
# 2. Read gpredict.cfg for preferences
# ---------------------------------------------------------------
DEFAULT_QTH=""
UNIT_SETTING=""
TFORMAT_SETTING=""
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    # GPredict uses USE_IMPERIAL and USE_LOCAL_TIME keys (not unit= or TFORMAT=)
    UNIT_SETTING=$(grep -i "^USE_IMPERIAL=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    TFORMAT_SETTING=$(grep -i "^USE_LOCAL_TIME=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# ---------------------------------------------------------------
# 3. Read POES_Tracking.mod
# ---------------------------------------------------------------
POES_EXISTS="false"
POES_SATELLITES=""
POES_QTHFILE=""
POES_GRID=""
POES_MOD_CONTENT=""
POES_SHOW_TERMINATOR=""
POES_MAP_FILE=""
POES_COLUMNS=""

# Search for any .mod file with "poes" in the name
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "poes"; then
        POES_EXISTS="true"
        POES_MOD_CONTENT=$(cat "$mod" 2>/dev/null)
        POES_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        POES_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        POES_GRID=$(grep -i "^GRID=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        POES_SHOW_TERMINATOR=$(grep -i "^SHOW_TERMINATOR=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        POES_MAP_FILE=$(grep -i "^MAP_FILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        POES_COLUMNS=$(grep -i "^COLUMNS=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# Check for individual satellite IDs in the module
POES_HAS_25338="false"
POES_HAS_28654="false"
POES_HAS_33591="false"
POES_HAS_38771="false"
POES_HAS_43689="false"
POES_HAS_37849="false"
POES_HAS_25544="false"
POES_HAS_20580="false"
POES_HAS_28474="false"

if [ -n "$POES_SATELLITES" ]; then
    echo "$POES_SATELLITES" | grep -q "25338" && POES_HAS_25338="true"
    echo "$POES_SATELLITES" | grep -q "28654" && POES_HAS_28654="true"
    echo "$POES_SATELLITES" | grep -q "33591" && POES_HAS_33591="true"
    echo "$POES_SATELLITES" | grep -q "38771" && POES_HAS_38771="true"
    echo "$POES_SATELLITES" | grep -q "43689" && POES_HAS_43689="true"
    echo "$POES_SATELLITES" | grep -q "37849" && POES_HAS_37849="true"
    echo "$POES_SATELLITES" | grep -q "25544" && POES_HAS_25544="true"
    echo "$POES_SATELLITES" | grep -q "20580" && POES_HAS_20580="true"
    echo "$POES_SATELLITES" | grep -q "28474" && POES_HAS_28474="true"
fi

# ---------------------------------------------------------------
# 4. Check pass prediction export file
# ---------------------------------------------------------------
PASS_FILE="/home/ga/Documents/METOP_C_passes.txt"
PASS_FILE_EXISTS="false"
PASS_FILE_SIZE=0
PASS_FILE_MTIME=0
PASS_FILE_HEAD=""
PASS_FILE_CONTAINS_METOP="false"

# Also check common filename variants the agent might use
for candidate in \
    "/home/ga/Documents/METOP_C_passes.txt" \
    "/home/ga/Documents/METOP-C-passes.txt" \
    "/home/ga/Documents/METOP-C_passes.txt" \
    "/home/ga/Documents/metop_c_passes.txt" \
    "/home/ga/Documents/METOP C-passes.txt"; do
    if [ -f "$candidate" ]; then
        PASS_FILE="$candidate"
        PASS_FILE_EXISTS="true"
        PASS_FILE_SIZE=$(stat -c %s "$candidate" 2>/dev/null || echo "0")
        PASS_FILE_MTIME=$(stat -c %Y "$candidate" 2>/dev/null || echo "0")
        PASS_FILE_HEAD=$(head -20 "$candidate" 2>/dev/null || echo "")
        if echo "$PASS_FILE_HEAD" | grep -qi "metop"; then
            PASS_FILE_CONTAINS_METOP="true"
        fi
        break
    fi
done

# ---------------------------------------------------------------
# 5. Write JSON result
# ---------------------------------------------------------------
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ' | tr '\r' ' '
}

cat > "$RESULT_FILE" << EOF
{
    "task_start_time": $TASK_START,
    "wallops_exists": $WALLOPS_EXISTS,
    "wallops_lat": "$(escape_json "$WALLOPS_LAT")",
    "wallops_lon": "$(escape_json "$WALLOPS_LON")",
    "wallops_alt": "$(escape_json "$WALLOPS_ALT")",
    "wallops_wx": "$(escape_json "$WALLOPS_WX")",
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "unit_setting": "$(escape_json "$UNIT_SETTING")",
    "tformat_setting": "$(escape_json "$TFORMAT_SETTING")",
    "poes_exists": $POES_EXISTS,
    "poes_satellites": "$(escape_json "$POES_SATELLITES")",
    "poes_qthfile": "$(escape_json "$POES_QTHFILE")",
    "poes_grid": "$(escape_json "$POES_GRID")",
    "poes_show_terminator": "$(escape_json "$POES_SHOW_TERMINATOR")",
    "poes_map_file": "$(escape_json "$POES_MAP_FILE")",
    "poes_columns": "$(escape_json "$POES_COLUMNS")",
    "poes_has_noaa15": $POES_HAS_25338,
    "poes_has_noaa18": $POES_HAS_28654,
    "poes_has_noaa19": $POES_HAS_33591,
    "poes_has_metopb": $POES_HAS_38771,
    "poes_has_metopc": $POES_HAS_43689,
    "poes_has_suominpp": $POES_HAS_37849,
    "poes_still_has_iss": $POES_HAS_25544,
    "poes_still_has_hubble": $POES_HAS_20580,
    "poes_still_has_gps": $POES_HAS_28474,
    "pass_file_exists": $PASS_FILE_EXISTS,
    "pass_file_size": $PASS_FILE_SIZE,
    "pass_file_mtime": $PASS_FILE_MTIME,
    "pass_file_contains_metop": $PASS_FILE_CONTAINS_METOP,
    "pass_file_head": "$(escape_json "$PASS_FILE_HEAD")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="
