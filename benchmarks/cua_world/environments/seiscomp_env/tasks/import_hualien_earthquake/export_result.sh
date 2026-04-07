#!/bin/bash
echo "=== Exporting import_hualien_earthquake results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_EVENT_COUNT=$(cat /tmp/initial_event_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check File Creation and Validity
FILE_PATH="/home/ga/Documents/hualien_earthquake.scml"
FILE_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
IS_VALID_XML="false"
FILE_SIZE="0"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
    
    MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    # Check XML validity (basic parsing)
    if python3 -c "import xml.etree.ElementTree as ET; ET.parse('$FILE_PATH')" 2>/dev/null; then
        IS_VALID_XML="true"
    fi
fi

# 2. Query Database State
CURRENT_EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")

# Extract Origin Data (look for Taiwan coordinates)
ORIGIN_DATA=$(mysql -u sysop -psysop seiscomp -N -e "SELECT latitude_value, longitude_value, depth_value, creationInfo_agencyID, time_value FROM Origin WHERE latitude_value BETWEEN 23.0 AND 24.5 AND longitude_value BETWEEN 121.0 AND 122.0 ORDER BY _oid DESC LIMIT 1;" 2>/dev/null)

ORIGIN_LAT=""
ORIGIN_LON=""
ORIGIN_DEPTH=""
ORIGIN_AGENCY=""
ORIGIN_TIME=""

if [ -n "$ORIGIN_DATA" ]; then
    ORIGIN_LAT=$(echo "$ORIGIN_DATA" | cut -f1)
    ORIGIN_LON=$(echo "$ORIGIN_DATA" | cut -f2)
    ORIGIN_DEPTH=$(echo "$ORIGIN_DATA" | cut -f3)
    ORIGIN_AGENCY=$(echo "$ORIGIN_DATA" | cut -f4)
    ORIGIN_TIME=$(echo "$ORIGIN_DATA" | cut -f5)
fi

# Extract Magnitude Data
MAG_DATA=$(mysql -u sysop -psysop seiscomp -N -e "SELECT magnitude_value, type FROM Magnitude WHERE magnitude_value >= 7.2 AND magnitude_value <= 7.6 ORDER BY _oid DESC LIMIT 1;" 2>/dev/null)

MAG_VALUE=""
MAG_TYPE=""

if [ -n "$MAG_DATA" ]; then
    MAG_VALUE=$(echo "$MAG_DATA" | cut -f1)
    MAG_TYPE=$(echo "$MAG_DATA" | cut -f2)
fi

# Extract Event Description
EVENT_DESC=$(mysql -u sysop -psysop seiscomp -N -e "SELECT text FROM EventDescription WHERE text LIKE '%Hualien%' LIMIT 1;" 2>/dev/null)
DESC_FOUND="false"
if [ -n "$EVENT_DESC" ]; then
    DESC_FOUND="true"
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "is_valid_xml": $IS_VALID_XML,
    "file_size_bytes": $FILE_SIZE,
    "initial_event_count": $INITIAL_EVENT_COUNT,
    "current_event_count": $CURRENT_EVENT_COUNT,
    "origin": {
        "latitude": "$ORIGIN_LAT",
        "longitude": "$ORIGIN_LON",
        "depth": "$ORIGIN_DEPTH",
        "agency": "$ORIGIN_AGENCY",
        "time": "$ORIGIN_TIME"
    },
    "magnitude": {
        "value": "$MAG_VALUE",
        "type": "$MAG_TYPE"
    },
    "description_found": $DESC_FOUND,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="