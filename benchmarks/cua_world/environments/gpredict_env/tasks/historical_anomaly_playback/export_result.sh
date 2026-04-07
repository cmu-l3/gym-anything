#!/bin/bash
echo "=== Exporting historical_anomaly_playback result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# --- Check Agent's Requested Screenshot ---
EVIDENCE_SCREENSHOT="/home/ga/incident_reconstruction.png"
EVIDENCE_EXISTS="false"
EVIDENCE_SIZE="0"
EVIDENCE_CREATED_DURING_TASK="false"

if [ -f "$EVIDENCE_SCREENSHOT" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_SCREENSHOT" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EVIDENCE_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_CREATED_DURING_TASK="true"
    fi
fi

# --- Read Tromso QTH (scan by latitude ~69.6) ---
TROMSO_EXISTS="false"
TROMSO_LAT=""
TROMSO_LON=""
TROMSO_ALT=""
TROMSO_QTH_NAME=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "69" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | cut -d. -f1)
        if [ "$lon_int" = "18" ]; then
            TROMSO_EXISTS="true"
            TROMSO_QTH_NAME=$(basename "$qth")
            TROMSO_LAT="$lat"
            TROMSO_LON="$lon"
            TROMSO_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Read Incident_Recon.mod ---
MODULE_EXISTS="false"
MODULE_SATELLITES=""
MODULE_QTHFILE=""
MODULE_HAS_SUOMI="false"
MODULE_HAS_DMSP="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "incident"; then
        MODULE_EXISTS="true"
        MODULE_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        MODULE_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2)
        
        if echo "$MODULE_SATELLITES" | grep -q "37849"; then MODULE_HAS_SUOMI="true"; fi
        if echo "$MODULE_SATELLITES" | grep -q "35951"; then MODULE_HAS_DMSP="true"; fi
        break
    fi
done

# --- Check UTC time setting in gpredict.cfg ---
UTC_TIME_ENABLED="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
if [ -f "$GPREDICT_CFG" ]; then
    UTC_VAL=$(grep -i "^utc=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UTC_VAL" = "1" ]; then
        UTC_TIME_ENABLED="true"
    fi
fi

# Check if application is running
APP_RUNNING=$(pgrep -x "gpredict" > /dev/null && echo "true" || echo "false")

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_size": $EVIDENCE_SIZE,
    "evidence_created_during_task": $EVIDENCE_CREATED_DURING_TASK,
    "tromso_exists": $TROMSO_EXISTS,
    "tromso_qth_name": "$(escape_json "$TROMSO_QTH_NAME")",
    "tromso_lat": "$(escape_json "$TROMSO_LAT")",
    "tromso_lon": "$(escape_json "$TROMSO_LON")",
    "tromso_alt": "$(escape_json "$TROMSO_ALT")",
    "module_exists": $MODULE_EXISTS,
    "module_satellites": "$(escape_json "$MODULE_SATELLITES")",
    "module_qthfile": "$(escape_json "$MODULE_QTHFILE")",
    "module_has_suomi": $MODULE_HAS_SUOMI,
    "module_has_dmsp": $MODULE_HAS_DMSP,
    "utc_time_enabled": $UTC_TIME_ENABLED
}
EOF

# Move to final location safely
rm -f /tmp/historical_anomaly_playback_result.json 2>/dev/null || sudo rm -f /tmp/historical_anomaly_playback_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/historical_anomaly_playback_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/historical_anomaly_playback_result.json
chmod 666 /tmp/historical_anomaly_playback_result.json 2>/dev/null || sudo chmod 666 /tmp/historical_anomaly_playback_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/historical_anomaly_playback_result.json"
cat /tmp/historical_anomaly_playback_result.json
echo "=== Export complete ==="