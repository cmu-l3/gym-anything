#!/bin/bash
# Export script for export_stargazing_passes task

echo "=== Exporting export_stargazing_passes result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
DOCUMENTS_DIR="/home/ga/Documents"
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check for Ground Station (Cherry Springs) ---
QTH_EXISTS="false"
QTH_NAME=""
QTH_LAT=""
QTH_LON=""
QTH_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # Check by coordinate proximity (Lat ~41.6)
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    
    # Or check by name match
    if [ "$lat_int" = "41" ] || echo "$basename_qth" | grep -qi "cherry"; then
        QTH_EXISTS="true"
        QTH_NAME="$basename_qth"
        QTH_LAT="$lat"
        QTH_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        QTH_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Check MIN_EL Preference ---
MIN_EL_VAL=""
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
if [ -f "$GPREDICT_CFG" ]; then
    MIN_EL_VAL=$(grep -i "^MIN_EL=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# --- Check Exported Files ---
check_file() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local is_new="false"
        if [ "$mtime" -gt "$TASK_START_TIME" ]; then
            is_new="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $is_new}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

ISS_FILE_JSON=$(check_file "${DOCUMENTS_DIR}/ISS_passes.txt")
CSS_FILE_JSON=$(check_file "${DOCUMENTS_DIR}/CSS_passes.txt")

# Ensure permissions on exported files so Python verifier can read them via copy_from_env
chmod 644 "${DOCUMENTS_DIR}/ISS_passes.txt" 2>/dev/null || true
chmod 644 "${DOCUMENTS_DIR}/CSS_passes.txt" 2>/dev/null || true

# --- Create JSON Output ---
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/export_stargazing_passes_result.json << EOF
{
    "task_start_time": $TASK_START_TIME,
    "qth_exists": $QTH_EXISTS,
    "qth_name": "$(escape_json "$QTH_NAME")",
    "qth_lat": "$(escape_json "$QTH_LAT")",
    "qth_lon": "$(escape_json "$QTH_LON")",
    "qth_alt": "$(escape_json "$QTH_ALT")",
    "min_el_val": "$(escape_json "$MIN_EL_VAL")",
    "iss_file": $ISS_FILE_JSON,
    "css_file": $CSS_FILE_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/export_stargazing_passes_result.json"
cat /tmp/export_stargazing_passes_result.json
echo ""
echo "=== Export Complete ==="