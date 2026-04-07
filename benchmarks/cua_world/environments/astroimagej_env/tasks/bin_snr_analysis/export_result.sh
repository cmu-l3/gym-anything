#!/bin/bash
echo "=== Exporting Bin SNR Analysis Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PROJECT_DIR="/home/ga/AstroImages/binning_analysis"
OUTPUT_DIR="$PROJECT_DIR/output"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run python script to analyze the outputs created by the agent
python3 << PYEOF
import json
import os
import re
from astropy.io import fits

OUTPUT_DIR = "$OUTPUT_DIR"
START_TIME = int("$START_TIME")

result = {
    "bin2x2_exists": False,
    "bin2x2_created_during_task": False,
    "bin2x2_w": 0,
    "bin2x2_h": 0,
    "bin4x4_exists": False,
    "bin4x4_created_during_task": False,
    "bin4x4_w": 0,
    "bin4x4_h": 0,
    "report_exists": False,
    "report_created_during_task": False,
    "report_content": "",
    "parsed_report": {}
}

bin2_file = os.path.join(OUTPUT_DIR, "ngc6652_bin2x2.fits")
if os.path.exists(bin2_file):
    result["bin2x2_exists"] = True
    mtime = os.path.getmtime(bin2_file)
    if mtime > START_TIME:
        result["bin2x2_created_during_task"] = True
    try:
        data = fits.getdata(bin2_file)
        if data.ndim == 2:
            result["bin2x2_h"], result["bin2x2_w"] = data.shape
        elif data.ndim >= 3:
            result["bin2x2_h"], result["bin2x2_w"] = data.shape[-2:]
    except Exception:
        pass

bin4_file = os.path.join(OUTPUT_DIR, "ngc6652_bin4x4.fits")
if os.path.exists(bin4_file):
    result["bin4x4_exists"] = True
    mtime = os.path.getmtime(bin4_file)
    if mtime > START_TIME:
        result["bin4x4_created_during_task"] = True
    try:
        data = fits.getdata(bin4_file)
        if data.ndim == 2:
            result["bin4x4_h"], result["bin4x4_w"] = data.shape
        elif data.ndim >= 3:
            result["bin4x4_h"], result["bin4x4_w"] = data.shape[-2:]
    except Exception:
        pass

report_file = os.path.join(OUTPUT_DIR, "binning_report.txt")
if os.path.exists(report_file):
    result["report_exists"] = True
    mtime = os.path.getmtime(report_file)
    if mtime > START_TIME:
        result["report_created_during_task"] = True
    
    try:
        with open(report_file, "r") as f:
            content = f.read()
            result["report_content"] = content
            
            # Parse key-value pairs
            for line in content.split('\\n'):
                line = line.strip()
                if ':' in line:
                    key, val = line.split(':', 1)
                    key = key.strip().lower()
                    # Extract just the number
                    val_match = re.search(r'[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?', val)
                    if val_match:
                        result["parsed_report"][key] = float(val_match.group(0))
    except Exception:
        pass

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="