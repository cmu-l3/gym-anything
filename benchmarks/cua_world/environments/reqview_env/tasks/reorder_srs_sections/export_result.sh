#!/bin/bash
echo "=== Exporting reorder_srs_sections results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Result Text File
RESULT_FILE="/home/ga/reorder_result.txt"
if [ -f "$RESULT_FILE" ]; then
    RESULT_EXISTS="true"
    RESULT_SIZE=$(stat -c %s "$RESULT_FILE")
    # Check if created during task
    RESULT_MTIME=$(stat -c %Y "$RESULT_FILE")
    if [ "$RESULT_MTIME" -gt "$TASK_START" ]; then
        RESULT_CREATED_DURING="true"
    else
        RESULT_CREATED_DURING="false"
    fi
else
    RESULT_EXISTS="false"
    RESULT_SIZE="0"
    RESULT_CREATED_DURING="false"
fi

# 2. Check SRS File Modification
SRS_PATH=$(cat /tmp/srs_file_path.txt 2>/dev/null)
SRS_MODIFIED="false"
SRS_HASH_CHANGED="false"

if [ -n "$SRS_PATH" ] && [ -f "$SRS_PATH" ]; then
    SRS_MTIME=$(stat -c %Y "$SRS_PATH")
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        SRS_MODIFIED="true"
    fi
    
    # Check hash against baseline
    CURRENT_HASH=$(md5sum "$SRS_PATH" | awk '{print $1}')
    BASELINE_HASH=$(cat /tmp/srs_baseline_hash.txt 2>/dev/null || echo "")
    
    if [ "$CURRENT_HASH" != "$BASELINE_HASH" ]; then
        SRS_HASH_CHANGED="true"
    fi
fi

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 4. Create Export JSON
TEMP_JSON=$(mktemp /tmp/export.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "result_file_exists": $RESULT_EXISTS,
    "result_file_created_during_task": $RESULT_CREATED_DURING,
    "srs_modified": $SRS_MODIFIED,
    "srs_hash_changed": $SRS_HASH_CHANGED,
    "srs_path_in_container": "$SRS_PATH",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export summary:"
cat /tmp/task_result.json
echo "=== Export complete ==="