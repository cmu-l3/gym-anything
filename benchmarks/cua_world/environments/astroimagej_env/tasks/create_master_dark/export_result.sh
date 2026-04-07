#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Record task end
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We calculate the FITS array metrics inside the container to avoid 
# copying hundreds of megabytes of raw FITS arrays to the host verifier.
cat > /tmp/evaluate_fits.py << 'EOF'
import json
import os
import glob
import numpy as np
from astropy.io import fits

result = {
    "output_exists": False,
    "created_after_start": False,
    "is_2d": False,
    "mae_median": None,
    "mae_average": None,
    "mae_single": None,
    "error_msg": None
}

output_path = "/home/ga/AstroImages/processed/master_dark.fits"
input_dir = "/home/ga/AstroImages/raw/darks"

if os.path.exists(output_path):
    result["output_exists"] = True
    
    try:
        # Check timestamp
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = float(f.read().strip())
        result["created_after_start"] = os.path.getmtime(output_path) > start_time
    except Exception as e:
        result["error_msg"] = f"Time check error: {e}"

    try:
        # Load agent's saved output
        with fits.open(output_path) as hdul:
            # Handle potential ImageJ saving formats (might put data in primary or first extension)
            agent_data = hdul[0].data if hdul[0].data is not None else hdul[1].data
            agent_data = agent_data.astype(float)
            result["is_2d"] = (agent_data.ndim == 2)
        
        # Calculate ground truths if output is 2D
        if result["is_2d"]:
            dark_files = sorted(glob.glob(os.path.join(input_dir, "*.fits")))
            stack = []
            for df in dark_files:
                with fits.open(df) as hdul:
                    data = hdul[0].data if hdul[0].data is not None else hdul[1].data
                    stack.append(data.astype(float))
            stack = np.array(stack)
            
            # Programmatically compute exact mathematical expected arrays
            gt_median = np.median(stack, axis=0)
            gt_average = np.mean(stack, axis=0)
            
            # Check Mean Absolute Errors against actual arrays to mathematically prove what they did
            result["mae_median"] = float(np.mean(np.abs(agent_data - gt_median)))
            result["mae_average"] = float(np.mean(np.abs(agent_data - gt_average)))
            result["mae_single"] = float(np.mean(np.abs(agent_data - stack[0])))
            
    except Exception as e:
        result["error_msg"] = str(e)

with open("/tmp/fits_evaluation.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/evaluate_fits.py

# Safely copy to standard result file for verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cp /tmp/fits_evaluation.json "$TEMP_JSON"
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="