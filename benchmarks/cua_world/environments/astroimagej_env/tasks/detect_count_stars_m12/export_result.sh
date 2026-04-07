#!/bin/bash
echo "=== Exporting Detect and Count Stars Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

MEASURE_DIR="/home/ga/AstroImages/measurements"

# Check if application is running
AIJ_RUNNING=$(pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null && echo "true" || echo "false")

# Use Python to evaluate the files and create the result JSON securely
cat << 'EOF' > /tmp/export_evaluation.py
import os
import json
import re

task_start = int(os.environ.get("TASK_START", 0))
measure_dir = "/home/ga/AstroImages/measurements"

result = {
    "catalog_exists": False,
    "catalog_created_during_task": False,
    "catalog_rows": 0,
    "catalog_has_coords": False,
    "catalog_has_brightness": False,
    "summary_exists": False,
    "summary_created_during_task": False,
    "reported_count": None,
    "aij_running": os.environ.get("AIJ_RUNNING") == "true"
}

# 1. Check Catalog File (accepting .csv, but also checking .xls or .txt just in case)
catalog_path = None
for ext in ['.csv', '.xls', '.txt', '.tsv']:
    p = os.path.join(measure_dir, f"m12_star_catalog{ext}")
    if os.path.exists(p):
        catalog_path = p
        break

if not catalog_path:
    # try any file that looks like a catalog
    import glob
    candidates = glob.glob(os.path.join(measure_dir, "*catalog*"))
    if candidates:
        catalog_path = candidates[0]

if catalog_path and os.path.exists(catalog_path):
    result["catalog_exists"] = True
    mtime = int(os.path.getmtime(catalog_path))
    if mtime >= task_start:
        result["catalog_created_during_task"] = True
        
    # Attempt to parse row count and headers safely
    try:
        with open(catalog_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]
            
        if lines:
            header = lines[0].lower()
            # Check for coordinates
            if re.search(r'\bx\b', header) and re.search(r'\by\b', header):
                result["catalog_has_coords"] = True
            
            # Check for brightness (Mean, Max, IntDen, Value, Area, etc.)
            if re.search(r'(mean|max|intden|value|area|flux)', header):
                result["catalog_has_brightness"] = True
                
            # Count data rows (skip header)
            result["catalog_rows"] = max(0, len(lines) - 1)
    except Exception as e:
        result["catalog_parse_error"] = str(e)

# 2. Check Summary File
summary_path = os.path.join(measure_dir, "m12_detection_summary.txt")
if os.path.exists(summary_path):
    result["summary_exists"] = True
    mtime = int(os.path.getmtime(summary_path))
    if mtime >= task_start:
        result["summary_created_during_task"] = True
        
    try:
        with open(summary_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        # Extract numbers from summary
        nums = re.findall(r'\d+', content)
        if nums:
            result["reported_count"] = int(nums[-1])  # take the last number assuming it's the count
    except Exception as e:
        result["summary_parse_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

export TASK_START AIJ_RUNNING
python3 /tmp/export_evaluation.py

# Ensure correct permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Result JSON saved:"
cat /tmp/task_result.json

echo "=== Export Complete ==="