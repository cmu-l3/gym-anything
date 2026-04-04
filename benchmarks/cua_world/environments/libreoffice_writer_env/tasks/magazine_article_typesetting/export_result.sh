#!/bin/bash
set -e
echo "=== Exporting Magazine Article Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/article_layout.odt"
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if output exists and get details
if [ -f "$OUTPUT_FILE" ]; then
    EXISTS="true"
    SIZE=$(stat -c %s "$OUTPUT_FILE")
    # Check if modified after task start
    START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    MOD_TIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$MOD_TIME" -gt "$START_TIME" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    EXISTS="false"
    SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Create result JSON
cat > "$RESULT_JSON" << EOF
{
    "output_exists": $EXISTS,
    "output_size_bytes": $SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"