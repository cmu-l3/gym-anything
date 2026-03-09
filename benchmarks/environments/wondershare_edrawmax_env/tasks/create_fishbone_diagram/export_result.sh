#!/bin/bash
set -e
echo "=== Exporting create_fishbone_diagram results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check EDDX File
EDDX_PATH="/home/ga/Diagrams/fishbone_outage_rca.eddx"
EDDX_EXISTS="false"
EDDX_SIZE="0"
EDDX_CREATED_DURING_TASK="false"

if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
    
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check PNG File
PNG_PATH="/home/ga/Diagrams/fishbone_outage_rca.png"
PNG_EXISTS="false"
PNG_SIZE="0"
PNG_CREATED_DURING_TASK="false"
PNG_WIDTH="0"
PNG_HEIGHT="0"

if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    fi

    # Try to get dimensions using identify (ImageMagick)
    if command -v identify >/dev/null; then
        DIMS=$(identify -format "%w %h" "$PNG_PATH" 2>/dev/null || echo "0 0")
        PNG_WIDTH=$(echo "$DIMS" | cut -d' ' -f1)
        PNG_HEIGHT=$(echo "$DIMS" | cut -d' ' -f2)
    fi
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size_bytes": $EDDX_SIZE,
    "eddx_created_during_task": $EDDX_CREATED_DURING_TASK,
    "png_exists": $PNG_EXISTS,
    "png_size_bytes": $PNG_SIZE,
    "png_created_during_task": $PNG_CREATED_DURING_TASK,
    "png_width": $PNG_WIDTH,
    "png_height": $PNG_HEIGHT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="