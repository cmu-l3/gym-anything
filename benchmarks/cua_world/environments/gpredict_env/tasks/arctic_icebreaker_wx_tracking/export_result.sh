#!/bin/bash
# Export script for arctic_icebreaker_wx_tracking task

echo "=== Exporting arctic_icebreaker_wx_tracking result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Function to safely escape strings for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# 1. Evaluate RV_Polarstern.qth
POLARSTERN_EXISTS="false"
POLARSTERN_LAT=""
POLARSTERN_LON=""
POLARSTERN_ALT=""
POLARSTERN_MTIME="0"

# Find qth file that might be named RV_Polarstern or similar
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "polarstern"; then
        POLARSTERN_EXISTS="true"
        POLARSTERN_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        POLARSTERN_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        POLARSTERN_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        POLARSTERN_MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
        break
    fi
done

# 2. Evaluate Arctic_WX.mod
ARCTIC_WX_EXISTS="false"
ARCTIC_WX_SATS=""
ARCTIC_WX_CONTENT=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "arctic"; then
        ARCTIC_WX_EXISTS="true"
        ARCTIC_WX_SATS=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        ARCTIC_WX_CONTENT=$(cat "$mod" | tr '\n' '|' | sed 's/"/\\"/g')
        break
    fi
done

# 3. Read gpredict.cfg
GPREDICT_CFG_CONTENT=""
DEFAULT_QTH=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    GPREDICT_CFG_CONTENT=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | tr '\n' '|' | sed 's/"/\\"/g')
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# 4. Read task timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Write JSON
cat > /tmp/arctic_icebreaker_result.json << EOF
{
    "polarstern_exists": $POLARSTERN_EXISTS,
    "polarstern_lat": "$(escape_json "$POLARSTERN_LAT")",
    "polarstern_lon": "$(escape_json "$POLARSTERN_LON")",
    "polarstern_alt": "$(escape_json "$POLARSTERN_ALT")",
    "polarstern_mtime": $POLARSTERN_MTIME,
    "arctic_wx_exists": $ARCTIC_WX_EXISTS,
    "arctic_wx_sats": "$(escape_json "$ARCTIC_WX_SATS")",
    "arctic_wx_content": "$(escape_json "$ARCTIC_WX_CONTENT")",
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

echo "Result saved to /tmp/arctic_icebreaker_result.json"
cat /tmp/arctic_icebreaker_result.json
echo ""
echo "=== Export Complete ==="