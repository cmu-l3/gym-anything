#!/bin/bash
echo "=== Exporting On-Orbit Sensor Calibration Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/on_orbit_sensor_calibration_start_ts 2>/dev/null || echo "0")
INITIAL_CLEAR_COUNT=$(cat /tmp/on_orbit_sensor_calibration_initial_clear_count 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/calibration_offsets.json"

FILE_EXISTS=false
FILE_IS_NEW=false
FILE_MTIME=0

if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
fi

# Query current CLEAR command count to verify agent sent CLEAR
CURRENT_CLEAR_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/on_orbit_sensor_calibration_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/on_orbit_sensor_calibration_end.png 2>/dev/null || true

cat > /tmp/on_orbit_sensor_calibration_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_clear_count": $INITIAL_CLEAR_COUNT,
    "current_clear_count": $CURRENT_CLEAR_COUNT
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "Initial CLEAR count: $INITIAL_CLEAR_COUNT"
echo "Current CLEAR count: $CURRENT_CLEAR_COUNT"
echo "=== Export Complete ==="