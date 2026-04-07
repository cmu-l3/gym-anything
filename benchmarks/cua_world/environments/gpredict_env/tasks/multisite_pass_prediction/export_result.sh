#!/bin/bash
# Export script for multisite_pass_prediction task

echo "=== Exporting multisite_pass_prediction result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# Helper function to extract ground station data
get_qth_data() {
    local qth_file="$1"
    if [ -f "$qth_file" ]; then
        local mtime=$(stat -c %Y "$qth_file" 2>/dev/null || echo "0")
        local lat=$(grep -i "^LAT=" "$qth_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        local lon=$(grep -i "^LON=" "$qth_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        local alt=$(grep -i "^ALT=" "$qth_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        echo "{\"exists\": true, \"lat\": \"$(escape_json "$lat")\", \"lon\": \"$(escape_json "$lon")\", \"alt\": \"$(escape_json "$alt")\", \"mtime\": $mtime}"
    else
        echo "{\"exists\": false, \"lat\": \"\", \"lon\": \"\", \"alt\": \"\", \"mtime\": 0}"
    fi
}

# Helper function to extract module data
get_mod_data() {
    local mod_file="$1"
    if [ -f "$mod_file" ]; then
        local mtime=$(stat -c %Y "$mod_file" 2>/dev/null || echo "0")
        local sats=$(grep -i "^SATELLITES=" "$mod_file" | head -1 | cut -d= -f2)
        local qth=$(grep -i "^QTHFILE=" "$mod_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        echo "{\"exists\": true, \"satellites\": \"$(escape_json "$sats")\", \"qthfile\": \"$(escape_json "$qth")\", \"mtime\": $mtime}"
    else
        echo "{\"exists\": false, \"satellites\": \"\", \"qthfile\": \"\", \"mtime\": 0}"
    fi
}

# Extract QTH Data
SVALBARD_JSON=$(get_qth_data "${GPREDICT_CONF_DIR}/Svalbard.qth")
SINGAPORE_JSON=$(get_qth_data "${GPREDICT_CONF_DIR}/Singapore.qth")
PUNTAARENAS_JSON=$(get_qth_data "${GPREDICT_CONF_DIR}/PuntaArenas.qth")

# Extract Mod Data
ARCTIC_JSON=$(get_mod_data "${GPREDICT_MOD_DIR}/Arctic_Tracking.mod")
EQUATORIAL_JSON=$(get_mod_data "${GPREDICT_MOD_DIR}/Equatorial_Tracking.mod")
SOUTHERN_JSON=$(get_mod_data "${GPREDICT_MOD_DIR}/Southern_Tracking.mod")

# --- Check UTC time setting in gpredict.cfg ---
UTC_TIME_ENABLED="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
if [ -f "$GPREDICT_CFG" ]; then
    UTC_VAL=$(grep -i "^utc=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UTC_VAL" = "1" ] || [ "$UTC_VAL" = "true" ]; then
        UTC_TIME_ENABLED="true"
    fi
fi

# Build result JSON
TEMP_JSON=$(mktemp /tmp/multisite_pass_prediction_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $START_TIME,
    "svalbard": $SVALBARD_JSON,
    "singapore": $SINGAPORE_JSON,
    "punta_arenas": $PUNTAARENAS_JSON,
    "arctic_tracking": $ARCTIC_JSON,
    "equatorial_tracking": $EQUATORIAL_JSON,
    "southern_tracking": $SOUTHERN_JSON,
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/multisite_pass_prediction_result.json 2>/dev/null || sudo rm -f /tmp/multisite_pass_prediction_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/multisite_pass_prediction_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/multisite_pass_prediction_result.json
chmod 666 /tmp/multisite_pass_prediction_result.json 2>/dev/null || sudo chmod 666 /tmp/multisite_pass_prediction_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/multisite_pass_prediction_result.json"
cat /tmp/multisite_pass_prediction_result.json
echo ""
echo "=== Export Complete ==="