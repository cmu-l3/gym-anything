#!/bin/bash
echo "=== Exporting apply_color_lut task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time and get start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target output file
OUTPUT_PATH="/home/ga/DICOM/exports/colorized_ct.png"

# Initialize result variables
EXISTS="false"
CREATED_DURING_TASK="false"
FILE_SIZE="0"
COLOR_DATA='{"valid": false}'

# Check if the expected output file exists
if [ -f "$OUTPUT_PATH" ]; then
    EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Verify file was created during the task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Perform color analysis on the exported image inside the container
    # Uses PIL/numpy which are installed in the environment
    COLOR_DATA=$(python3 << PYEOF
import json
import numpy as np
try:
    from PIL import Image
    # Open and convert to RGB
    img = Image.open("$OUTPUT_PATH").convert('RGB')
    arr = np.array(img)
    
    # Separate channels
    r = arr[:, :, 0].astype(float)
    g = arr[:, :, 1].astype(float)
    b = arr[:, :, 2].astype(float)
    
    # Calculate channel means
    mean_r = float(r.mean())
    mean_g = float(g.mean())
    mean_b = float(b.mean())
    
    # Calculate mean absolute differences between channels
    # A grayscale image will have near 0 difference across R, G, and B
    diff_rg = np.abs(r - g).mean()
    diff_gb = np.abs(g - b).mean()
    diff_rb = np.abs(r - b).mean()
    mean_abs_diff = float((diff_rg + diff_gb + diff_rb) / 3.0)
    
    print(json.dumps({
        "valid": True,
        "mean_r": mean_r,
        "mean_g": mean_g,
        "mean_b": mean_b,
        "mean_abs_diff": mean_abs_diff
    }))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
)
fi

# Check if Weasis was running
APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "color_analysis": $COLOR_DATA,
    "app_was_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to final destination
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="