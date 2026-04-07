#!/bin/bash
echo "=== Exporting mpr_mip_rendering task result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing/processing
take_screenshot /tmp/task_final.png

EXPORT_PATH="/home/ga/DICOM/exports/mip_projection.png"
EXPORT_EXISTS="false"
CREATED_DURING_TASK="false"
EXPORT_SIZE=0
BRIGHT_PIXELS=0
TOTAL_PIXELS=0
PROGRAMMATIC_ERROR=""

# Check file existence and timestamps
if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$EXPORT_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Calculate physics metrics using Python to verify MIP
    # A standard slice has a small cross-section of the vessel (~900 bright pixels)
    # A 15mm MIP captures the diagonal length of the vessel (~3000+ bright pixels)
    METRICS=$(python3 << 'PYEOF'
import json
import sys
try:
    from PIL import Image
    import numpy as np
    
    img = Image.open("/home/ga/DICOM/exports/mip_projection.png").convert('L')
    data = np.array(img)
    
    # Count pixels that are very bright (the contrast-filled vessel)
    bright_pixels = int(np.sum(data > 200))
    total_pixels = int(data.size)
    
    print(json.dumps({
        "bright_pixels": bright_pixels,
        "total_pixels": total_pixels
    }))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
    )
    
    BRIGHT_PIXELS=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('bright_pixels', 0))" 2>/dev/null || echo "0")
    TOTAL_PIXELS=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_pixels', 0))" 2>/dev/null || echo "0")
    PROGRAMMATIC_ERROR=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error', ''))" 2>/dev/null || echo "")
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "export_exists": $EXPORT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "export_size_bytes": $EXPORT_SIZE,
    "bright_pixels": $BRIGHT_PIXELS,
    "total_pixels": $TOTAL_PIXELS,
    "app_was_running": $APP_RUNNING,
    "programmatic_error": "$PROGRAMMATIC_ERROR"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="