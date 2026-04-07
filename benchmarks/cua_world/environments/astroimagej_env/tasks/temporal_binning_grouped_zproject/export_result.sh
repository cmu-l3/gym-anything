#!/bin/bash
echo "=== Exporting Temporal Binning Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

BINNED_DIR="/home/ga/AstroImages/time_series/binned"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract data using Python
cat > /tmp/extract_results.py << 'EOF'
import os
import glob
import json
import re

BINNED_DIR = "/home/ga/AstroImages/time_series/binned"
TASK_START = int(os.environ.get("TASK_START", 0))

result = {
    "binned_file_found": False,
    "binned_file_path": None,
    "binned_file_created_during_task": False,
    "binned_frame_count": 0,
    "report_found": False,
    "reported_raw_std": None,
    "reported_binned_std": None,
    "reported_reduction_factor": None
}

# 1. Look for the binned image stack
potential_files = glob.glob(os.path.join(BINNED_DIR, "wasp12_binned_10x.tif*")) + \
                  glob.glob(os.path.join(BINNED_DIR, "wasp12_binned_10x.fit*"))

if potential_files:
    best_file = potential_files[0]
    result["binned_file_found"] = True
    result["binned_file_path"] = best_file
    
    mtime = os.path.getmtime(best_file)
    if mtime >= TASK_START:
        result["binned_file_created_during_task"] = True
        
    # Attempt to read frame count
    if best_file.endswith(('.fits', '.fit')):
        try:
            from astropy.io import fits
            with fits.open(best_file) as hdul:
                data = hdul[0].data
                if data is not None and len(data.shape) >= 3:
                    result["binned_frame_count"] = data.shape[0]
                elif data is not None and len(data.shape) == 2:
                    result["binned_frame_count"] = 1
        except Exception:
            pass
    elif best_file.endswith(('.tif', '.tiff')):
        try:
            from PIL import Image
            with Image.open(best_file) as img:
                result["binned_frame_count"] = getattr(img, "n_frames", 1)
        except Exception:
            pass

# 2. Look for the noise report
report_path = os.path.join(BINNED_DIR, "noise_report.txt")
if os.path.exists(report_path):
    result["report_found"] = True
    try:
        with open(report_path, 'r') as f:
            content = f.read()
            
            raw_match = re.search(r'Raw_StdDev:\s*([0-9.]+)', content, re.IGNORECASE)
            if raw_match:
                result["reported_raw_std"] = float(raw_match.group(1))
                
            binned_match = re.search(r'Binned_StdDev:\s*([0-9.]+)', content, re.IGNORECASE)
            if binned_match:
                result["reported_binned_std"] = float(binned_match.group(1))
                
            factor_match = re.search(r'Reduction_Factor:\s*([0-9.]+)', content, re.IGNORECASE)
            if factor_match:
                result["reported_reduction_factor"] = float(factor_match.group(1))
                
    except Exception as e:
        result["report_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

export TASK_START
python3 /tmp/extract_results.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export Complete ==="