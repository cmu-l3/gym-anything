#!/bin/bash
# Export script for radiometric_cal_field_setup task

echo "=== Exporting radiometric_cal_field_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# --- 1. Read Railroad_Valley.qth ---
QTH_EXISTS="false"
QTH_LAT=""
QTH_LON=""
QTH_ALT=""
QTH_MTIME="0"

# Find any QTH file created during task that matches "Railroad" or coordinates
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # Identify the target file
    if echo "$basename_qth" | grep -qi "railroad"; then
        QTH_EXISTS="true"
        QTH_MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
        QTH_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        QTH_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        QTH_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- 2. Read Vicarious_Cal.mod ---
MOD_EXISTS="false"
MOD_SATELLITES=""
MOD_QTHFILE=""
MOD_LAYOUT=""
MOD_MTIME="0"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    
    if echo "$modname" | grep -qi "vicarious"; then
        MOD_EXISTS="true"
        MOD_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        MOD_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        MOD_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        MOD_LAYOUT=$(grep -i "^LAYOUT=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- 3. Read global preferences (gpredict.cfg) ---
PREF_MIN_EL=""
PREF_UTC="0"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"

if [ -f "$GPREDICT_CFG" ]; then
    PREF_MIN_EL=$(grep -i "^min_el=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    PREF_UTC=$(grep -i "^utc=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# Check if application was running at the end
APP_RUNNING="false"
if pgrep -x "gpredict" > /dev/null; then
    APP_RUNNING="true"
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START_TIME,
    "app_was_running": $APP_RUNNING,
    
    "qth_exists": $QTH_EXISTS,
    "qth_mtime": $QTH_MTIME,
    "qth_lat": "$(escape_json "$QTH_LAT")",
    "qth_lon": "$(escape_json "$QTH_LON")",
    "qth_alt": "$(escape_json "$QTH_ALT")",
    
    "mod_exists": $MOD_EXISTS,
    "mod_mtime": $MOD_MTIME,
    "mod_satellites": "$(escape_json "$MOD_SATELLITES")",
    "mod_qthfile": "$(escape_json "$MOD_QTHFILE")",
    "mod_layout": "$(escape_json "$MOD_LAYOUT")",
    
    "pref_min_el": "$(escape_json "$PREF_MIN_EL")",
    "pref_utc": "$(escape_json "$PREF_UTC")",
    
    "export_timestamp": $(date +%s)
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="