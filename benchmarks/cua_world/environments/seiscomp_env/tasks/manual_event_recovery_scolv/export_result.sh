#!/bin/bash
echo "=== Exporting task results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# ─── 1. Check Output File ────────────────────────────────────────────────
OUTPUT_PATH="/home/ga/recovered_event.xml"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
XML_VALID="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Simple check if it's an XML file containing SeisComP elements
    if grep -qi "seiscomp\|origin\|event" "$OUTPUT_PATH"; then
        XML_VALID="true"
    fi
fi

# ─── 2. Query Database for Agent's Work ──────────────────────────────────
echo "Querying SeisComP Database for manual origin and magnitudes..."

ORIGIN_FOUND="false"
ORIGIN_LAT="0"
ORIGIN_LON="0"
ORIGIN_ID=""

MAG_FOUND="false"
MAG_VALUE="0"
MAG_STATION_COUNT="0"

# Find latest origin
ORIGIN_DATA=$(mysql -u sysop -psysop seiscomp -B -N -e "SELECT publicID, latitude_value, longitude_value FROM Origin ORDER BY _oid DESC LIMIT 1" 2>/dev/null)

if [ -n "$ORIGIN_DATA" ]; then
    ORIGIN_FOUND="true"
    ORIGIN_ID=$(echo "$ORIGIN_DATA" | cut -f1)
    ORIGIN_LAT=$(echo "$ORIGIN_DATA" | cut -f2)
    ORIGIN_LON=$(echo "$ORIGIN_DATA" | cut -f3)
    
    echo "Found Origin: $ORIGIN_ID at Lat: $ORIGIN_LAT, Lon: $ORIGIN_LON"
    
    # Find magnitudes linked to this origin
    MAG_DATA=$(mysql -u sysop -psysop seiscomp -B -N -e "SELECT publicID, magnitude_value FROM Magnitude WHERE originID='$ORIGIN_ID' ORDER BY magnitude_value DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$MAG_DATA" ]; then
        MAG_FOUND="true"
        MAG_ID=$(echo "$MAG_DATA" | cut -f1)
        MAG_VALUE=$(echo "$MAG_DATA" | cut -f2)
        
        echo "Found Magnitude: $MAG_VALUE ($MAG_ID)"
        
        # Count stations used for this magnitude
        MAG_STATION_COUNT=$(mysql -u sysop -psysop seiscomp -B -N -e "SELECT COUNT(*) FROM StationMagnitude WHERE magnitudeID='$MAG_ID'" 2>/dev/null)
        echo "Stations used: $MAG_STATION_COUNT"
    else
        echo "No Magnitude found linked to Origin $ORIGIN_ID."
    fi
else
    echo "No Origin found in database."
fi

# ─── 3. Construct JSON Result ────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file": {
        "exists": $OUTPUT_EXISTS,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "is_valid_xml": $XML_VALID
    },
    "database": {
        "origin_found": $ORIGIN_FOUND,
        "origin_id": "$ORIGIN_ID",
        "origin_lat": $ORIGIN_LAT,
        "origin_lon": $ORIGIN_LON,
        "magnitude_found": $MAG_FOUND,
        "magnitude_value": $MAG_VALUE,
        "station_count": $MAG_STATION_COUNT
    }
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="