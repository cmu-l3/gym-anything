#!/bin/bash
echo "=== Exporting Database Replay Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Database State
# We want to know:
# - Total count of PROCESSED
# - Count of PENDING (should be 0)
# - Details of the rows that SHOULD have been processed (id 1, 2, 4)
# - Timestamps of updates

DB_STATE_JSON=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c "
SELECT row_to_json(t) FROM (
  SELECT 
    (SELECT COUNT(*) FROM integration_queue WHERE status = 'PROCESSED') as processed_count,
    (SELECT COUNT(*) FROM integration_queue WHERE status = 'PENDING') as pending_count,
    (
      SELECT json_agg(row_data) FROM (
        SELECT id, status, EXTRACT(EPOCH FROM processed_at) as processed_ts 
        FROM integration_queue 
        WHERE id IN (1, 2, 4)
      ) row_data
    ) as target_rows
) t;
")

# 2. Check File Output
# Count files in output dir
FILE_COUNT=$(ls -1 /tmp/processed_hl7/*.hl7 2>/dev/null | wc -l || echo "0")

# Check if files have content
FILES_VALID="true"
if [ "$FILE_COUNT" -gt 0 ]; then
    if grep -q "MSH" /tmp/processed_hl7/*.hl7 2>/dev/null; then
        FILES_VALID="true"
    else
        FILES_VALID="false"
    fi
else
    FILES_VALID="false"
fi

# 3. Check Channel Status
# We'll use the API to get channel status
CHANNEL_ID=$(get_channel_id "Staging_Table_Processor" 2>/dev/null || echo "")
CHANNEL_STATUS="UNKNOWN"
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Assemble JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_state": $DB_STATE_JSON,
    "file_output": {
        "count": $FILE_COUNT,
        "valid_content": $FILES_VALID,
        "directory_exists": $([ -d "/tmp/processed_hl7" ] && echo "true" || echo "false")
    },
    "channel_info": {
        "id": "$CHANNEL_ID",
        "status": "$CHANNEL_STATUS"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json