#!/bin/bash
echo "=== Exporting apply_spatial_filter task result ==="

source /workspace/scripts/task_utils.sh

# Take final proof screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_PATH="/home/ga/DICOM/exports/sharpened_ct.tiff"
NOTE_PATH="/home/ga/DICOM/exports/filter_applied.txt"

EXPORT_EXISTS="false"
EXPORT_SIZE="0"
EXPORT_CREATED_DURING_TASK="false"
IS_TIFF="false"

# Check the exported TIFF
if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
        EXPORT_CREATED_DURING_TASK="true"
    fi
    
    # Strictly verify format is TIFF using PIL magic byte inspection
    IS_TIFF=$(python3 -c "
import sys
try:
    from PIL import Image
    img = Image.open('$EXPORT_PATH')
    print('true' if img.format == 'TIFF' else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")
fi

# Extract Note details
NOTE_EXISTS="false"
NOTE_CONTENT=""
if [ -f "$NOTE_PATH" ]; then
    NOTE_EXISTS="true"
    NOTE_CONTENT=$(cat "$NOTE_PATH" 2>/dev/null | head -n 1 | tr -d '\r' | tr -d '"' | tr -d '\\')
fi

# Compare the agent's TIFF against baseline (inside the container where CV2 is guaranteed)
AGENT_VAR="0"
BASELINE_VAR="0"
if [ -f "/var/lib/weasis_ground_truth/baseline_stats.json" ]; then
    BASELINE_VAR=$(cat "/var/lib/weasis_ground_truth/baseline_stats.json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('laplacian_var', 0))" 2>/dev/null || echo "0")
fi

if [ "$EXPORT_EXISTS" = "true" ] && [ "$IS_TIFF" = "true" ]; then
    AGENT_VAR=$(python3 << 'PYEOF'
import cv2
import sys
try:
    img = cv2.imread('/home/ga/DICOM/exports/sharpened_ct.tiff', cv2.IMREAD_GRAYSCALE)
    if img is not None:
        print(cv2.Laplacian(img, cv2.CV_64F).var())
    else:
        print("0")
except:
    print("0")
PYEOF
)
fi

# Export all metrics securely to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "export_exists": $EXPORT_EXISTS,
    "export_created_during_task": $EXPORT_CREATED_DURING_TASK,
    "export_size_bytes": $EXPORT_SIZE,
    "is_tiff": $IS_TIFF,
    "note_exists": $NOTE_EXISTS,
    "note_content": "$NOTE_CONTENT",
    "agent_laplacian_var": $AGENT_VAR,
    "baseline_laplacian_var": $BASELINE_VAR,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="