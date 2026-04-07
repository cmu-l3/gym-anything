#!/bin/bash
echo "=== Exporting Eagle Nebula Line Profile Results ==="

source /workspace/scripts/task_utils.sh

# Final screenshot
take_screenshot /tmp/task_final.png ga

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
MEASURE_DIR="/home/ga/AstroImages/measurements"

python3 << 'PYEOF'
import json
import os
import re
import glob

TASK_START = int(os.environ.get("TASK_START", 0))
MEASURE_DIR = "/home/ga/AstroImages/measurements"

result = {
    "csv_exists": False,
    "csv_created_during_task": False,
    "csv_rows": 0,
    "summary_exists": False,
    "summary_created_during_task": False,
    "parsed_summary": {}
}

# 1. Check CSV/Data file
# Agent might name it .csv, .txt, .tsv
data_files = glob.glob(f"{MEASURE_DIR}/eagle_ha_profile.*")
if data_files:
    data_file = data_files[0]
    result["csv_exists"] = True
    mtime = os.path.getmtime(data_file)
    if mtime > TASK_START:
        result["csv_created_during_task"] = True
    
    # Count rows
    try:
        with open(data_file, 'r') as f:
            lines = f.readlines()
            result["csv_rows"] = len([l for l in lines if l.strip()])
    except Exception:
        pass

# 2. Check Summary file
summary_file = f"{MEASURE_DIR}/profile_summary.txt"
if os.path.isfile(summary_file):
    result["summary_exists"] = True
    mtime = os.path.getmtime(summary_file)
    if mtime > TASK_START:
        result["summary_created_during_task"] = True
        
    # Parse summary file
    try:
        with open(summary_file, 'r') as f:
            content = f.read()
            
        patterns = {
            "PEAK_INTENSITY": r"PEAK_INTENSITY:\s*([0-9\.\-\+eE]+)",
            "PEAK_POSITION_X": r"PEAK_POSITION_X:\s*([0-9\.\-\+eE]+)",
            "MEAN_BACKGROUND": r"MEAN_BACKGROUND:\s*([0-9\.\-\+eE]+)",
            "PROFILE_LENGTH": r"PROFILE_LENGTH:\s*([0-9\.\-\+eE]+)",
            "FWHM_PIXELS": r"FWHM_PIXELS:\s*([0-9\.\-\+eE]+)"
        }
        
        parsed = {}
        for key, pattern in patterns.items():
            match = re.search(pattern, content, re.IGNORECASE)
            if match:
                try:
                    parsed[key] = float(match.group(1))
                except ValueError:
                    parsed[key] = None
        
        result["parsed_summary"] = parsed
    except Exception as e:
        result["summary_parse_error"] = str(e)

# Save result JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="