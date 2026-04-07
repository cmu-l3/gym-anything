#!/bin/bash
echo "=== Exporting Timeline Maintenance Schedule Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/timeline_maintenance_schedule_start_ts 2>/dev/null || echo "0")
INITIAL_TIMELINE_COUNT=$(cat /tmp/timeline_maintenance_schedule_initial_count 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/timeline_schedule.json"

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

# Query current timeline count from COSMOS REST API
TOKEN=$(get_cosmos_token 2>/dev/null || echo "Cosmos2024!")
CURRENT_TIMELINES=$(curl -s -H "Authorization: $TOKEN" \
    "$OPENC3_URL/openc3-api/timeline/DEFAULT" 2>/dev/null || echo "[]")
CURRENT_TIMELINE_COUNT=$(echo "$CURRENT_TIMELINES" | jq 'length' 2>/dev/null || echo "0")

echo "Initial timeline count: $INITIAL_TIMELINE_COUNT"
echo "Current timeline count: $CURRENT_TIMELINE_COUNT"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/timeline_maintenance_schedule_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/timeline_maintenance_schedule_end.png 2>/dev/null || true

cat > /tmp/timeline_maintenance_schedule_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_timeline_count": $INITIAL_TIMELINE_COUNT,
    "current_timeline_count": $CURRENT_TIMELINE_COUNT
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="
