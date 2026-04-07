#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SCML_PATH="/home/ga/rapid_station.scml"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Check the SCML file artifact
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$SCML_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$SCML_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$SCML_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Query Database for expected values
echo "Querying SeisComP database..."

# Query Network
NET_EXISTS=$(mysql -u sysop -psysop seiscomp -N -B -e "SELECT count(*) FROM Network WHERE code='TR'" 2>/dev/null || echo "0")

# Query Station Lat/Lon
STA_DATA=$(mysql -u sysop -psysop seiscomp -N -B -e "
SELECT s.latitude, s.longitude 
FROM Station s 
JOIN Network n ON s._parent_oid = n._oid 
WHERE s.code='RAPID' AND n.code='TR' LIMIT 1" 2>/dev/null || echo "")

STA_LAT="null"
STA_LON="null"
if [ -n "$STA_DATA" ]; then
    STA_LAT=$(echo "$STA_DATA" | awk '{print $1}')
    STA_LON=$(echo "$STA_DATA" | awk '{print $2}')
fi

# Query Stream and Sample Rate
STREAM_DATA=$(mysql -u sysop -psysop seiscomp -N -B -e "
SELECT st.sampleRateNumerator, st.sampleRateDenominator
FROM Stream st 
JOIN SensorLocation sl ON st._parent_oid = sl._oid 
JOIN Station s ON sl._parent_oid = s._oid 
JOIN Network n ON s._parent_oid = n._oid 
WHERE st.code='BHZ' AND s.code='RAPID' AND n.code='TR' LIMIT 1" 2>/dev/null || echo "")

STREAM_NUM="0"
STREAM_DEN="1"
if [ -n "$STREAM_DATA" ]; then
    STREAM_NUM=$(echo "$STREAM_DATA" | awk '{print $1}')
    STREAM_DEN=$(echo "$STREAM_DATA" | awk '{print $2}')
fi

# 4. Construct JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "db_network_tr_exists": $([ "$NET_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "db_station_lat": $STA_LAT,
    "db_station_lon": $STA_LON,
    "db_stream_num": $STREAM_NUM,
    "db_stream_den": $STREAM_DEN,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Safely copy to destination
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="