#!/bin/bash
echo "=== Exporting create_binary_source_mask Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Check timestamps to verify file was created DURING the task
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/AstroImages/masking/source_mask.fits"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Export variable so python script can read it
export FILE_CREATED_DURING_TASK

# Analyze results using Python
python3 << 'PYEOF'
import os
import json
import sys

try:
    from astropy.io import fits
    import numpy as np
    
    orig_path = "/home/ga/AstroImages/masking/hst_wfpc2_sample.fits"
    mask_path = "/home/ga/AstroImages/masking/source_mask.fits"
    
    file_created = os.environ.get("FILE_CREATED_DURING_TASK") == "true"
    
    res = {
        "mask_exists": os.path.exists(mask_path),
        "valid_fits": False,
        "dim_match": False,
        "unique_vals": 0,
        "is_binary": False,
        "source_mean": 0.0,
        "bg_mean": 0.0,
        "alignment_valid": False,
        "source_area": 0,
        "baseline_area": 0,
        "dilation_valid": False,
        "file_created_during_task": file_created,
        "error": None
    }
    
    if res["mask_exists"]:
        try:
            with fits.open(orig_path) as hdul_orig, fits.open(mask_path) as hdul_mask:
                orig_data = hdul_orig[0].data
                mask_data = hdul_mask[0].data
                
                res["valid_fits"] = True
                
                if orig_data is not None and mask_data is not None:
                    if orig_data.shape == mask_data.shape:
                        res["dim_match"] = True
                        
                        # Use np.unique, filter out NaNs if any
                        unique_vals = np.unique(mask_data[~np.isnan(mask_data)])
                        res["unique_vals"] = len(unique_vals)
                        
                        # Strict binary check
                        if len(unique_vals) == 2:
                            res["is_binary"] = True
                            v0, v1 = unique_vals
                            
                            # Calculate means in the original image to see which corresponds to the "source"
                            m0 = float(np.nanmean(orig_data[mask_data == v0]))
                            m1 = float(np.nanmean(orig_data[mask_data == v1]))
                            
                            if m0 > m1:
                                source_val, bg_val = v0, v1
                                res["source_mean"], res["bg_mean"] = m0, m1
                            else:
                                source_val, bg_val = v1, v0
                                res["source_mean"], res["bg_mean"] = m1, m0
                                
                            # The source mask should cover bright pixels (stars), so its mean should be much higher than background
                            # Check if the ratio is at least 1.5x to confirm successful alignment
                            if res["bg_mean"] != 0:
                                res["alignment_valid"] = (res["source_mean"] > res["bg_mean"] * 1.5)
                            else:
                                res["alignment_valid"] = True # Handle div by zero edge case
                            
                            res["source_area"] = int(np.sum(mask_data == source_val))
                            
                            # Calculate a strict baseline threshold area (99th percentile) to compare with agent's mask
                            thresh = np.nanpercentile(orig_data, 99.0)
                            res["baseline_area"] = int(np.sum(orig_data > thresh))
                            
                            # If dilated, source area should be significantly larger than a strict baseline
                            # (But not the whole image!) We expect at least a 10% increase from 99th percentile
                            # and obviously < 50% of the image
                            if res["source_area"] >= res["baseline_area"] * 1.1 and res["source_area"] < orig_data.size * 0.5:
                                res["dilation_valid"] = True
        except Exception as e:
            res["error"] = str(e)
            
    with open("/tmp/task_result.json", "w") as f:
        json.dump(res, f)
except Exception as e:
    with open("/tmp/task_result.json", "w") as f:
        json.dump({"error": str(e)}, f)

PYEOF

echo "Analysis JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="