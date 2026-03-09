#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_ANALYSIS_ID=$(cat /tmp/target_analysis_id.txt 2>/dev/null || echo "9001")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# Check Database for Attachment
# ---------------------------------------------------------------
# Query specifically for attachments linked to our ComplianceAnalysis ID
# created > start_time ensures it was added during this session
# We select count, and details of the last added one
DB_RESULT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "
    SELECT 
        COUNT(*),
        original_filename,
        file,
        created
    FROM attachments 
    WHERE model='ComplianceAnalysis' 
    AND foreign_key=${TARGET_ANALYSIS_ID}
    AND deleted=0
    ORDER BY created DESC LIMIT 1;
" 2>/dev/null)

# Parse result
# Default values
ATTACHMENT_COUNT=0
FILENAME=""
STORED_FILENAME=""
CREATED_TIME=""

if [ -n "$DB_RESULT" ]; then
    ATTACHMENT_COUNT=$(echo "$DB_RESULT" | awk '{print $1}')
    FILENAME=$(echo "$DB_RESULT" | awk '{print $2}')
    STORED_FILENAME=$(echo "$DB_RESULT" | awk '{print $3}')
    CREATED_TIME=$(echo "$DB_RESULT" | cut -f4-) # Timestamp might have spaces
fi

# Check timestamps relative to task start (SQL timestamp vs Epoch)
# Convert SQL timestamp to epoch if exists
CREATED_EPOCH=0
if [ -n "$CREATED_TIME" ] && [ "$CREATED_TIME" != "NULL" ]; then
    CREATED_EPOCH=$(date -d "$CREATED_TIME" +%s 2>/dev/null || echo "0")
fi

NEWLY_CREATED="false"
if [ "$CREATED_EPOCH" -ge "$TASK_START" ]; then
    NEWLY_CREATED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_analysis_id": $TARGET_ANALYSIS_ID,
    "attachment_found_count": $ATTACHMENT_COUNT,
    "last_attachment_filename": "$FILENAME",
    "last_attachment_created_epoch": $CREATED_EPOCH,
    "is_newly_created": $NEWLY_CREATED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="