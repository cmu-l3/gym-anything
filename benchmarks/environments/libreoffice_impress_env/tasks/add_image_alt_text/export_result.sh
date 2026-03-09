#!/bin/bash
set -euo pipefail
echo "=== Exporting Add Image Alt Text Result ==="

OUTPUT_FILE="/home/ga/Documents/Presentations/community_impact_accessible.odp"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check output file
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_FILE"
}
EOF

# Ensure readable
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"