#!/bin/bash
# Export script for Directory Tree Visualization task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Directory Tree Visualization Result ==="

# Take final screenshot (captures the visualization window if open)
take_screenshot /tmp/task_final_screenshot.png

OUTPUT_PATH="/home/ga/Documents/SEO/reports/site_tree.png"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_FRESH="false"
FILE_SIZE_BYTES=0
IS_PNG="false"
SF_RUNNING="false"

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Check the output file
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        FILE_FRESH="true"
    fi
    
    # Check size
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check file header for PNG magic bytes
    if file "$OUTPUT_PATH" | grep -qi "PNG image data"; then
        IS_PNG="true"
    fi
    
    # Copy file to /tmp for easier retrieval by verification script if needed
    cp "$OUTPUT_PATH" /tmp/exported_site_tree.png 2>/dev/null || true
    chmod 644 /tmp/exported_site_tree.png 2>/dev/null || true
fi

# Check for Visualization Window presence in window list
VISUALIZATION_OPEN="false"
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
if echo "$WINDOW_LIST" | grep -qi "Directory Tree\|Force-Directed\|Visualization"; then
    VISUALIZATION_OPEN="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sf_running": $SF_RUNNING,
    "visualization_window_open": $VISUALIZATION_OPEN,
    "file_exists": $FILE_EXISTS,
    "file_fresh": $FILE_FRESH,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "is_png_format": $IS_PNG,
    "output_path": "$OUTPUT_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="