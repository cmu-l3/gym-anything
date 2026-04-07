#!/bin/bash
echo "=== Exporting Stack Exposures Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
OUTPUT_FITS="/home/ga/AstroImages/stacking_project/output/median_stack.fits"
OUTPUT_REPORT="/home/ga/AstroImages/stacking_project/output/snr_report.txt"

# Analyze the generated FITS file with Python
python3 << 'PYEOF'
import os, json, re
import numpy as np
from astropy.io import fits

OUTPUT_FITS = "/home/ga/AstroImages/stacking_project/output/median_stack.fits"
OUTPUT_REPORT = "/home/ga/AstroImages/stacking_project/output/snr_report.txt"

result = {
    "fits_exists": os.path.isfile(OUTPUT_FITS),
    "fits_mtime": os.path.getmtime(OUTPUT_FITS) if os.path.isfile(OUTPUT_FITS) else 0,
    "fits_size_bytes": os.path.getsize(OUTPUT_FITS) if os.path.isfile(OUTPUT_FITS) else 0,
    "report_exists": os.path.isfile(OUTPUT_REPORT),
    "report_mtime": os.path.getmtime(OUTPUT_REPORT) if os.path.isfile(OUTPUT_REPORT) else 0,
    "report_content": "",
    "fits_stats": {},
    "parsed_report": {}
}

# Analyze FITS image
if result["fits_exists"]:
    try:
        with fits.open(OUTPUT_FITS) as hdul:
            data = hdul[0].data
            if data is not None:
                # Handle 3D stacks if agent accidentally saved the whole sequence instead of Z-project
                is_3d = len(data.shape) > 2
                if is_3d:
                    result["fits_stats"]["is_stack"] = True
                    result["fits_stats"]["shape"] = list(data.shape)
                else:
                    result["fits_stats"]["is_stack"] = False
                    result["fits_stats"]["shape"] = list(data.shape)
                    result["fits_stats"]["mean"] = float(np.nanmean(data))
                    result["fits_stats"]["std"] = float(np.nanstd(data))
                    
                    # Calculate sky std in the same region used for ground truth
                    cy, cx = data.shape[0]//2, data.shape[1]//2
                    if cy > 500 and cx > 500:
                        sky_region = data[cy-500:cy-300, cx-500:cx-300]
                        result["fits_stats"]["sky_std"] = float(np.nanstd(sky_region))
    except Exception as e:
        result["fits_error"] = str(e)

# Analyze Report
if result["report_exists"]:
    try:
        with open(OUTPUT_REPORT, 'r') as f:
            content = f.read()
            result["report_content"] = content
            
        # Parse fields
        for line in content.split('\n'):
            line = line.strip()
            if not line: continue
            
            if re.search(r'SNR_single[:\s=]+([0-9.]+)', line, re.IGNORECASE):
                result["parsed_report"]["snr_single"] = float(re.search(r'([0-9.]+)', line).group(1))
            elif re.search(r'SNR_stacked[:\s=]+([0-9.]+)', line, re.IGNORECASE):
                result["parsed_report"]["snr_stacked"] = float(re.search(r'([0-9.]+)', line).group(1))
            elif re.search(r'Improvement_factor[:\s=]+([0-9.]+)', line, re.IGNORECASE):
                result["parsed_report"]["improvement_factor"] = float(re.search(r'([0-9.]+)', line).group(1))
            elif re.search(r'N_frames[:\s=]+([0-9]+)', line, re.IGNORECASE):
                result["parsed_report"]["n_frames"] = int(re.search(r'([0-9]+)', line).group(1))
                
    except Exception as e:
        result["report_error"] = str(e)

# Check if AIJ is running
import subprocess
try:
    subprocess.check_output(["pgrep", "-f", "AstroImageJ"])
    result["aij_running"] = True
except:
    result["aij_running"] = False

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="