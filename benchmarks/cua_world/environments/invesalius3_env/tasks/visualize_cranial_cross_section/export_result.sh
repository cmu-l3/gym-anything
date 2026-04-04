#!/bin/bash
echo "=== Exporting visualize_cranial_cross_section result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/skull_cross_section.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Take final system screenshot (evidence of screen state)
take_screenshot /tmp/task_final.png

# Check the agent's exported file
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
IS_PNG="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Check timestamp
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check magic bytes for PNG
    if file "$OUTPUT_FILE" | grep -q "PNG image data"; then
        IS_PNG="true"
    fi
fi

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "is_png": $IS_PNG,
    "output_path": "$OUTPUT_FILE",
    "system_screenshot": "/tmp/task_final.png"
}
EOF

# Ensure permissions for verify script to read
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png 2>/dev/null || true
if [ -f "$OUTPUT_FILE" ]; then
    chmod 644 "$OUTPUT_FILE"
fi

echo "Export complete."
cat /tmp/task_result.json