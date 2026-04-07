#!/bin/bash
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/hta_audit_report.csv"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output file status
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Capture MySQL history to verify database interaction (soft check)
# We check if mysql was run or if the user accessed the database
DB_INTERACTION="false"
if grep -q "mysql" /home/ga/.bash_history 2>/dev/null; then
    DB_INTERACTION="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "db_interaction_detected": $DB_INTERACTION,
    "screenshot_path": "/tmp/task_final.png",
    "output_content_path": "/tmp/hta_audit_report_copy.csv"
}
EOF

# Copy the CSV content for the verifier to analyze
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_PATH" /tmp/hta_audit_report_copy.csv
    chmod 666 /tmp/hta_audit_report_copy.csv
fi

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"