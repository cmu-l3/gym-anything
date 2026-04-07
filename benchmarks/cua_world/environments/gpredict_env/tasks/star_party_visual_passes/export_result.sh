#!/bin/bash
# Export script for star_party_visual_passes task

echo "=== Exporting star_party_visual_passes result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
OUTPUT_FILE="/home/ga/Documents/iss_visible_passes.txt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check Exported File ---
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Copy file to /tmp for verifier access
    cp "$OUTPUT_FILE" "/tmp/exported_passes.txt"
    chmod 666 "/tmp/exported_passes.txt"
fi

# --- Find Griffith QTH (scan by lat ~34.1, lon ~-118.3) ---
GRIFFITH_EXISTS="false"
GRIFFITH_QTH_NAME=""
GRIFFITH_LAT=""
GRIFFITH_LON=""
GRIFFITH_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "34" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_abs=$(echo "$lon" | sed 's/-//')
        lon_int=$(echo "$lon_abs" | cut -d. -f1)
        if [ "$lon_int" = "118" ]; then
            GRIFFITH_EXISTS="true"
            GRIFFITH_QTH_NAME=$(basename "$qth" .qth)
            GRIFFITH_LAT="$lat"
            GRIFFITH_LON="$lon"
            GRIFFITH_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Check UI State (is the pass prediction window open?) ---
PASS_WINDOW_OPEN="false"
WINDOWS=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null)
if echo "$WINDOWS" | grep -qi "Upcoming passes\|Future passes\|passes for ISS"; then
    PASS_WINDOW_OPEN="true"
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/star_party_visual_passes_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "griffith_exists": $GRIFFITH_EXISTS,
    "griffith_qth_name": "$(escape_json "$GRIFFITH_QTH_NAME")",
    "griffith_lat": "$(escape_json "$GRIFFITH_LAT")",
    "griffith_lon": "$(escape_json "$GRIFFITH_LON")",
    "griffith_alt": "$(escape_json "$GRIFFITH_ALT")",
    "pass_window_open": $PASS_WINDOW_OPEN,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/star_party_visual_passes_result.json"
cat /tmp/star_party_visual_passes_result.json
echo "=== Export Complete ==="