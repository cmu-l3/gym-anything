#!/bin/bash
# Export script for telemetry_doppler_tuning_setup task

echo "=== Exporting telemetry_doppler_tuning_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot (CRITICAL for VLM)
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Read Kiruna QTH ---
KIRUNA_EXISTS="false"
KIRUNA_LAT=""
KIRUNA_LON=""
KIRUNA_ALT=""

# Scan for any Kiruna or coordinate-matching QTH
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # Try name first
    if echo "$basename_qth" | grep -qi "kiruna"; then
        KIRUNA_EXISTS="true"
        KIRUNA_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        KIRUNA_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        KIRUNA_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
    
    # Try lat fallback
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "67" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | cut -d. -f1)
        if [ "$lon_int" = "21" ]; then
            KIRUNA_EXISTS="true"
            KIRUNA_LAT="$lat"
            KIRUNA_LON="$lon"
            KIRUNA_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Read HRPT_Downlink Module ---
HRPT_MOD_EXISTS="false"
HRPT_MOD_NAME=""
HRPT_SATELLITES=""
HRPT_QTHFILE=""
HRPT_MOD_CONTENT=""
HRPT_CREATED_DURING_TASK="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    
    # Look for HRPT in the filename or module config
    if echo "$modname" | grep -qi "hrpt"; then
        HRPT_MOD_EXISTS="true"
        HRPT_MOD_NAME="$modname"
        HRPT_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        HRPT_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2)
        HRPT_MOD_CONTENT=$(cat "$mod" | tr '\n' '|' | sed 's/"/\\"/g')
        
        MOD_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        if [ "$MOD_MTIME" -gt "$TASK_START" ]; then
            HRPT_CREATED_DURING_TASK="true"
        fi
        break
    fi
done

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/telemetry_doppler_tuning_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "kiruna_exists": $KIRUNA_EXISTS,
    "kiruna_lat": "$(escape_json "$KIRUNA_LAT")",
    "kiruna_lon": "$(escape_json "$KIRUNA_LON")",
    "kiruna_alt": "$(escape_json "$KIRUNA_ALT")",
    "hrpt_mod_exists": $HRPT_MOD_EXISTS,
    "hrpt_mod_name": "$(escape_json "$HRPT_MOD_NAME")",
    "hrpt_satellites": "$(escape_json "$HRPT_SATELLITES")",
    "hrpt_qthfile": "$(escape_json "$HRPT_QTHFILE")",
    "hrpt_created_during_task": $HRPT_CREATED_DURING_TASK,
    "hrpt_mod_content": "$(escape_json "$HRPT_MOD_CONTENT")",
    "screenshot_path": "/tmp/task_end_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/telemetry_doppler_tuning_result.json"
cat /tmp/telemetry_doppler_tuning_result.json
echo ""
echo "=== Export Complete ==="