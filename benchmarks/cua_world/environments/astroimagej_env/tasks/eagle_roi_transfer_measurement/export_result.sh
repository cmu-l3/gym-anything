#!/bin/bash
echo "=== Exporting Eagle ROI Transfer Task ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Parse the agent's output files using Python and export to a structured JSON for verification
python3 << 'PYEOF'
import csv
import json
import os
import re

csv_file = "/home/ga/AstroImages/measurements/roi_measurements.csv"
txt_file = "/home/ga/AstroImages/measurements/excitation_ratio.txt"

result = {
    "csv_exists": False,
    "txt_exists": False,
    "num_rows": 0,
    "row1": {},
    "row2": {},
    "reported_ratio": None,
    "csv_columns": []
}

if os.path.exists(csv_file):
    result["csv_exists"] = True
    try:
        with open(csv_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            result["num_rows"] = len(rows)
            if reader.fieldnames:
                result["csv_columns"] = reader.fieldnames
                
            if len(rows) >= 1:
                result["row1"] = rows[0]
            if len(rows) >= 2:
                result["row2"] = rows[1]
    except Exception as e:
        result["csv_error"] = str(e)

if os.path.exists(txt_file):
    result["txt_exists"] = True
    try:
        with open(txt_file, 'r', encoding='utf-8') as f:
            content = f.read().strip()
            # Try to extract the first floating point number
            match = re.search(r'[-+]?\d*\.\d+|\d+', content)
            if match:
                result["reported_ratio"] = float(match.group(0))
    except Exception as e:
        result["txt_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "Export complete"