#!/bin/bash
echo "=== Exporting create_wireframe_mockup results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
TARGET_DIR="/home/ga/Diagrams"
EDDX_FILE="$TARGET_DIR/patient_portal_wireframe.eddx"
PNG_FILE="$TARGET_DIR/patient_portal_wireframe.png"

# Check EDDX File
EDDX_EXISTS="false"
EDDX_SIZE="0"
EDDX_CREATED_DURING_TASK="false"
if [ -f "$EDDX_FILE" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_FILE" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_FILE" 2>/dev/null || echo "0")
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING_TASK="true"
    fi
fi

# Check PNG File
PNG_EXISTS="false"
PNG_SIZE="0"
PNG_CREATED_DURING_TASK="false"
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_FILE" 2>/dev/null || echo "0")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot (fallback if PNG export failed)
take_screenshot /tmp/task_final.png

# Create result JSON
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
    "eddx_path": "$EDDX_FILE",
    "png_path": "$PNG_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json