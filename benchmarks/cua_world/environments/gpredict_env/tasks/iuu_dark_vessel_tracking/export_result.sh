#!/bin/bash
echo "=== Exporting iuu_dark_vessel_tracking result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Initialize export variables
GALAPAGOS_EXISTS="false"
GALAPAGOS_QTH_NAME=""
GALAPAGOS_LAT=""
GALAPAGOS_LON=""
GALAPAGOS_ALT=""

MODULE_EXISTS="false"
MODULE_SATELLITES=""
MODULE_QTHFILE=""

GPREDICT_CFG_CONTENT=""

# 1. Look for Galapagos ground station
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # Check if name contains Galapagos
    if echo "$basename_qth" | grep -qi "galapagos"; then
        GALAPAGOS_EXISTS="true"
        GALAPAGOS_QTH_NAME="$basename_qth"
        GALAPAGOS_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        GALAPAGOS_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        GALAPAGOS_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# 2. Look for Dark_Vessels module
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    basename_mod=$(basename "$mod" .mod)
    
    if echo "$basename_mod" | grep -qi "dark\|vessel"; then
        MODULE_EXISTS="true"
        MODULE_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        MODULE_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        break
    fi
done

# 3. Read gpredict.cfg for Map settings
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    GPREDICT_CFG_CONTENT=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | tr '\n' '|' | sed 's/"/\\"/g')
fi

# Escape variables for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/task_result.json << EOF
{
    "galapagos_exists": $GALAPAGOS_EXISTS,
    "galapagos_qth_name": "$(escape_json "$GALAPAGOS_QTH_NAME")",
    "galapagos_lat": "$(escape_json "$GALAPAGOS_LAT")",
    "galapagos_lon": "$(escape_json "$GALAPAGOS_LON")",
    "galapagos_alt": "$(escape_json "$GALAPAGOS_ALT")",
    "module_exists": $MODULE_EXISTS,
    "module_satellites": "$(escape_json "$MODULE_SATELLITES")",
    "module_qthfile": "$(escape_json "$MODULE_QTHFILE")",
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end_time": $(date +%s)
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="