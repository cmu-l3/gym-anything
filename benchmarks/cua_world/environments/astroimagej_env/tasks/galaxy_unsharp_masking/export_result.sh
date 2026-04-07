#!/bin/bash
echo "=== Exporting galaxy_unsharp_masking result ==="

source /workspace/scripts/task_utils.sh

# Take final state screenshot
take_screenshot /tmp/task_final.png

# Record end time and check file presence
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/AstroImages/processed/galaxy_highpass.fits"

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if application is running
APP_RUNNING="false"
if is_aij_running; then
    APP_RUNNING="true"
fi

# Create a partial JSON with basic checks
cat > /tmp/partial_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING
}
EOF

# Run programmatic mathematical verification in Python (using env's Astropy/SciPy)
cat > /tmp/check_math.py << 'EOF'
import json, sys, os
import numpy as np
from astropy.io import fits
from scipy.ndimage import gaussian_filter

with open('/tmp/partial_result.json', 'r') as f:
    result = json.load(f)

orig_path = "/home/ga/AstroImages/raw/uit_galaxy_sample.fits"
out_path = "/home/ga/AstroImages/processed/galaxy_highpass.fits"

result["math_success"] = False
result["math_error"] = None

if result.get("output_exists", False):
    try:
        with fits.open(orig_path) as hdul_orig:
            orig_data = hdul_orig[0].data.astype(np.float32)
            
        with fits.open(out_path) as hdul_out:
            out_data = hdul_out[0].data.astype(np.float32)
            
        if orig_data.shape == out_data.shape:
            # Recreate ground truth logic programmatically
            # Agent is expected to have subtracted a 15-pixel Gaussian Blur
            blurred = gaussian_filter(orig_data, sigma=15.0)
            gt_highpass = orig_data - blurred
            
            # Crop 10 pixels from edges to avoid convolution boundary differences between SciPy and ImageJ
            border = 10
            out_crop = out_data[border:-border, border:-border]
            gt_crop = gt_highpass[border:-border, border:-border]
            orig_crop = orig_data[border:-border, border:-border]
            
            # Mean Absolute Error comparisons
            mae_vs_gt = float(np.mean(np.abs(out_crop - gt_crop)))
            mae_vs_orig = float(np.mean(np.abs(out_crop - orig_crop)))
            mae_vs_zeros = float(np.mean(np.abs(out_crop)))
            
            result["math_success"] = True
            result["mae_vs_gt"] = mae_vs_gt
            result["mae_vs_orig"] = mae_vs_orig
            result["mae_vs_zeros"] = mae_vs_zeros
        else:
            result["math_error"] = f"Shape mismatch: Original {orig_data.shape} vs Output {out_data.shape}"
            
    except Exception as e:
        result["math_error"] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Execute math check
su - ga -c "python3 /tmp/check_math.py" 2>/dev/null || mv /tmp/partial_result.json /tmp/task_result.json

# Close AstroImageJ gracefully
close_astroimagej

# Finalize permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved:"
cat /tmp/task_result.json
echo "=== Export complete ==="