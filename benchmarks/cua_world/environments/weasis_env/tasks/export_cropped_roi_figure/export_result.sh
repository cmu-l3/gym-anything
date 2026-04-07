#!/bin/bash
echo "=== Exporting export_cropped_roi_figure task result ==="

source /workspace/scripts/task_utils.sh

# Record end state
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

OUTPUT_PATH="/home/ga/DICOM/exports/figure_roi.jpg"
OUTPUT_EXISTS="false"
CREATED_DURING_TASK="false"
FILE_SIZE="0"
IMG_WIDTH="0"
IMG_HEIGHT="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Try to extract image dimensions using Python
    DIMENSIONS=$(python3 << 'PYEOF'
import json
import sys
try:
    from PIL import Image
    img = Image.open("/home/ga/DICOM/exports/figure_roi.jpg")
    print(json.dumps({"width": img.width, "height": img.height}))
except Exception as e:
    print(json.dumps({"width": 0, "height": 0}))
PYEOF
)
    IMG_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))")
    IMG_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))")
fi

# Check Weasis logs for Export Dialog evidence
EXPORT_DIALOG_OPENED="false"
if grep -qiE "(export|save|image.*writer|jpeg)" /tmp/weasis_ga.log 2>/dev/null; then
    EXPORT_DIALOG_OPENED="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "image_width": $IMG_WIDTH,
    "image_height": $IMG_HEIGHT,
    "export_dialog_opened_logs": $EXPORT_DIALOG_OPENED
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="