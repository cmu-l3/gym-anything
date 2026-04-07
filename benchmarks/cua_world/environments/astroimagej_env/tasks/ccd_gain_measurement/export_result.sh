#!/bin/bash
echo "=== Exporting CCD Gain Measurement Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

WORK_DIR="/home/ga/AstroImages/gain_measurement"
RESULT_FILE="$WORK_DIR/ccd_gain_results.txt"

# 1. Parse the user's result file using Python to handle various formatting
python3 << PYEOF
import json
import os
import glob

result_file = "$RESULT_FILE"
output = {
    "file_exists": False,
    "file_modified_time": 0,
    "parsed_values": {},
    "measurement_files_found": 0,
    "image_calculator_used": False
}

if os.path.exists(result_file):
    output["file_exists"] = True
    output["file_modified_time"] = int(os.path.getmtime(result_file))
    
    with open(result_file, 'r') as f:
        lines = f.readlines()
        
    for line in lines:
        if ':' in line:
            parts = line.split(':', 1)
            key = parts[0].strip().lower()
            val_str = parts[1].strip()
            
            # Extract first valid float from string
            try:
                # Remove extra text and extract number
                import re
                match = re.search(r"[-+]?\d*\.\d+|\d+", val_str)
                if match:
                    output["parsed_values"][key] = float(match.group(0))
            except ValueError:
                pass

# Check for AIJ measurement tables as secondary evidence
meas_files = glob.glob(f"{WORK_DIR}/*.xls") + glob.glob(f"{WORK_DIR}/*.csv")
output["measurement_files_found"] = len(meas_files)

with open("/tmp/parsed_results.json", "w") as f:
    json.dump(output, f)
PYEOF

# 2. Merge parsed data and timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
AIJ_RUNNING=$(is_aij_running && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
python3 << PYEOF
import json

with open("/tmp/parsed_results.json", "r") as f:
    data = json.load(f)

data["task_start_time"] = $TASK_START
data["aij_running_at_end"] = $AIJ_RUNNING

with open("$TEMP_JSON", "w") as f:
    json.dump(data, f, indent=4)
PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json