#!/bin/bash
# Export script for Export Visitors API task

echo "=== Exporting Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_PATH="/home/ga/Documents/matomo_visitors_export.csv"

# Check file existence and metadata
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
CREATED_DURING_TASK="false"
HEADER_LINE=""
CONTENT_SAMPLE=""
LINE_COUNT="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Anti-gaming check
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Read content snippets for verification
    # Get header (first non-empty line)
    HEADER_LINE=$(grep -v "^$" "$OUTPUT_PATH" | head -n 1)
    
    # Get a few sample lines (to check for data rows)
    CONTENT_SAMPLE=$(head -n 10 "$OUTPUT_PATH" | base64 -w 0)
    
    # Count lines (to verify period=day/range result vs single summary)
    LINE_COUNT=$(wc -l < "$OUTPUT_PATH" 2>/dev/null || echo "0")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/export_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "created_during_task": $CREATED_DURING_TASK,
    "header_line": "$(echo "$HEADER_LINE" | sed 's/"/\\"/g')",
    "line_count": $LINE_COUNT,
    "content_sample_base64": "$CONTENT_SAMPLE",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="