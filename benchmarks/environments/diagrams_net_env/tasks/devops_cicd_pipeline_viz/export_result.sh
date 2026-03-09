#!/bin/bash
set -e
echo "=== Exporting DevOps CI/CD Pipeline Viz Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define paths
DRAWIO_PATH="/home/ga/Diagrams/pipeline_diagram.drawio"
PNG_PATH="/home/ga/Diagrams/pipeline_diagram.png"

# Check output files
DRAWIO_EXISTS="false"
DRAWIO_SIZE=0
DRAWIO_CREATED_DURING_TASK="false"

if [ -f "$DRAWIO_PATH" ]; then
    DRAWIO_EXISTS="true"
    DRAWIO_SIZE=$(stat -c %s "$DRAWIO_PATH")
    DRAWIO_MTIME=$(stat -c %Y "$DRAWIO_PATH")
    if [ "$DRAWIO_MTIME" -gt "$TASK_START" ]; then
        DRAWIO_CREATED_DURING_TASK="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
PNG_CREATED_DURING_TASK="false"

if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_path": "$DRAWIO_PATH",
    "drawio_size": $DRAWIO_SIZE,
    "drawio_created_during_task": $DRAWIO_CREATED_DURING_TASK,
    "png_exists": $PNG_EXISTS,
    "png_path": "$PNG_PATH",
    "png_size": $PNG_SIZE,
    "png_created_during_task": $PNG_CREATED_DURING_TASK
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"