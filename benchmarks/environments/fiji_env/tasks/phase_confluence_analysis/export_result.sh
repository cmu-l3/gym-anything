#!/bin/bash
echo "=== Exporting phase_confluence_analysis result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/Fiji_Data/results/confluence"
MASK_PATH="$RESULTS_DIR/confluence_mask.png"
REPORT_PATH="$RESULTS_DIR/confluence_report.txt"
GT_MASK="/var/lib/fiji/ground_truth/hela_gt.png"
GT_VALUE="/var/lib/fiji/ground_truth/expected_confluence.txt"

# Check output mask
MASK_EXISTS="false"
MASK_CREATED_DURING_TASK="false"
if [ -f "$MASK_PATH" ]; then
    MASK_EXISTS="true"
    MASK_MTIME=$(stat -c %Y "$MASK_PATH" 2>/dev/null || echo "0")
    if [ "$MASK_MTIME" -gt "$TASK_START" ]; then
        MASK_CREATED_DURING_TASK="true"
    fi
    # Copy to /tmp for easy verifier access via copy_from_env
    cp "$MASK_PATH" /tmp/agent_mask.png
fi

# Check report
REPORT_EXISTS="false"
REPORTED_VALUE=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Extract first number found in file
    REPORTED_VALUE=$(grep -oE "[0-9]+(\.[0-9]+)?" "$REPORT_PATH" | head -1 || echo "")
    cp "$REPORT_PATH" /tmp/agent_report.txt
fi

# Copy Ground Truth for verification
if [ -f "$GT_MASK" ]; then
    cp "$GT_MASK" /tmp/gt_mask.png
    cp "$GT_VALUE" /tmp/gt_value.txt
fi

# Calculate Jaccard Index INSIDE container (using env's python) to save verifier complexity
# We write the score to a file that the verifier reads
IOU_SCORE="0.0"
python3 -c "
import numpy as np
from skimage import io
import sys

try:
    if '$MASK_EXISTS' == 'true' and '$GT_MASK' != '':
        agent = io.imread('$MASK_PATH', as_gray=True) > 0
        gt = io.imread('$GT_MASK', as_gray=True) > 0
        
        # Resize agent mask to match GT if needed (handling potential size mismatch)
        if agent.shape != gt.shape:
            from skimage.transform import resize
            agent = resize(agent, gt.shape, order=0, anti_aliasing=False) > 0

        intersection = np.logical_and(agent, gt)
        union = np.logical_or(agent, gt)
        iou = np.sum(intersection) / np.sum(union) if np.sum(union) > 0 else 0.0
        print(f'{iou:.4f}')
    else:
        print('0.0')
except Exception:
    print('0.0')
" > /tmp/iou_score.txt 2>/dev/null || echo "0.0" > /tmp/iou_score.txt

IOU_SCORE=$(cat /tmp/iou_score.txt)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "mask_exists": $MASK_EXISTS,
    "mask_created_during_task": $MASK_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "reported_value": "$REPORTED_VALUE",
    "iou_score": $IOU_SCORE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="