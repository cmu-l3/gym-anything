#!/bin/bash
echo "=== Exporting Ratiometric Analysis Results ==="
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define Paths
OUTPUT_IMG="/home/ga/ImageJ_Data/results/ratio_map.tif"
OUTPUT_TXT="/home/ga/ImageJ_Data/results/mean_ratio.txt"
GT_RED="/tmp/task_ground_truth/red_channel.tif"
GT_GREEN="/tmp/task_ground_truth/green_channel.tif"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check file timestamps and existence
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
TXT_EXISTS="false"

if [ -f "$OUTPUT_IMG" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$OUTPUT_IMG")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_TXT" ]; then
    TXT_EXISTS="true"
fi

# 4. Run Python Analysis Script
# This script compares the user's output against the ground truth derived from the raw channels.
# It checks bit depth, correlation, and masking.

python3 -c "
import sys
import json
import os
import numpy as np
from PIL import Image
import warnings

# Suppress warnings for clean output
warnings.filterwarnings('ignore')

result = {
    'file_exists': $FILE_EXISTS,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'txt_exists': $TXT_EXISTS,
    'is_float32': False,
    'correlation': 0.0,
    'masking_score': 0.0,
    'reported_mean': 0.0,
    'calculated_mean': 0.0,
    'error': ''
}

try:
    if result['file_exists']:
        # Load User Image
        try:
            user_img = Image.open('$OUTPUT_IMG')
            user_arr = np.array(user_img)
            
            # Check Mode/Bit Depth
            # PIL mode 'F' is 32-bit floating point
            if user_img.mode == 'F' or user_arr.dtype == np.float32:
                result['is_float32'] = True
            
            # Load Ground Truth Channels if available
            if os.path.exists('$GT_RED') and os.path.exists('$GT_GREEN'):
                red = np.array(Image.open('$GT_RED')).astype(np.float32)
                green = np.array(Image.open('$GT_GREEN')).astype(np.float32)
                
                # Avoid division by zero
                # Ground Truth Ratio calculation
                # Mask: Green > Threshold (Otsu approx or fixed small value)
                # Simple background check: Green > 10 (8-bit scale)
                mask = green > 15
                
                gt_ratio = np.zeros_like(red)
                np.divide(red, green, out=gt_ratio, where=mask)
                
                # Compare User vs GT inside the mask
                # Flatten valid pixels
                user_valid = user_arr[mask]
                gt_valid = gt_ratio[mask]
                
                # Check 1: Correlation of valid pixels
                if len(user_valid) > 0 and len(gt_valid) > 0:
                    corr = np.corrcoef(user_valid, gt_valid)[0, 1]
                    result['correlation'] = float(corr) if not np.isnan(corr) else 0.0
                    result['calculated_mean'] = float(np.mean(user_valid))
                
                # Check 2: Masking Accuracy
                # Pixels OUTSIDE the mask should be 0 or NaN in user image
                user_background = user_arr[~mask]
                # We allow 0 or NaN
                bg_zeros = np.sum(np.isclose(user_background, 0) | np.isnan(user_background))
                bg_total = user_background.size
                if bg_total > 0:
                    result['masking_score'] = float(bg_zeros / bg_total)
                else:
                    result['masking_score'] = 1.0 # No background?
            else:
                result['error'] = 'Ground truth source files missing'
                
        except Exception as e:
            result['error'] = f'Image analysis failed: {str(e)}'

    # Check Reported Mean
    if result['txt_exists']:
        try:
            with open('$OUTPUT_TXT', 'r') as f:
                val = f.read().strip()
                # Remove common text output if present (e.g., 'Mean: 1.23')
                import re
                nums = re.findall(r'[-+]?\d*\.\d+|\d+', val)
                if nums:
                    result['reported_mean'] = float(nums[0])
        except Exception as e:
            pass

except Exception as e:
    result['error'] = str(e)

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

echo "Result analysis complete."
cat /tmp/task_result.json