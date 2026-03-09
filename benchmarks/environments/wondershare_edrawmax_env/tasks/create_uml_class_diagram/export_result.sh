#!/bin/bash
echo "=== Exporting create_uml_class_diagram results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EDDX_PATH="/home/ga/Documents/patient_portal_class_diagram.eddx"
PNG_PATH="/home/ga/Documents/patient_portal_class_diagram.png"

# Gather stats for EDDX file
if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
else
    EDDX_EXISTS="false"
    EDDX_SIZE="0"
    EDDX_MTIME="0"
fi

# Gather stats for PNG file
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    
    # Get image dimensions if possible (using python/imagemagick if available)
    PNG_DIMS=$(identify -format "%wx%h" "$PNG_PATH" 2>/dev/null || echo "0x0")
else
    PNG_EXISTS="false"
    PNG_SIZE="0"
    PNG_MTIME="0"
    PNG_DIMS="0x0"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size_bytes": $EDDX_SIZE,
    "eddx_mtime": $EDDX_MTIME,
    "png_exists": $PNG_EXISTS,
    "png_size_bytes": $PNG_SIZE,
    "png_mtime": $PNG_MTIME,
    "png_dims": "$PNG_DIMS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="