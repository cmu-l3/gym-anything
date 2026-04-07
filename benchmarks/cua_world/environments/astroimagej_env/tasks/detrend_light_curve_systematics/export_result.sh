#!/bin/bash
echo "=== Exporting Detrend Light Curve Results ==="

source /workspace/scripts/task_utils.sh
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
PLOT_PATH="/home/ga/AstroImages/time_series/output/detrended_plot.png"
REPORT_PATH="/home/ga/AstroImages/time_series/output/detrend_report.txt"

# Analyze Results
python3 << PYEOF
import json
import os
import re

task_start = int("$TASK_START")
plot_path = "$PLOT_PATH"
report_path = "$REPORT_PATH"

result = {
    "plot_exists": False,
    "plot_created_during_task": False,
    "plot_size_bytes": 0,
    "report_exists": False,
    "report_created_during_task": False,
    "report_content": "",
    "reported_c1": None,
}

# Check Plot
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_bytes"] = os.path.getsize(plot_path)
    if os.path.getmtime(plot_path) > task_start:
        result["plot_created_during_task"] = True

# Check Report
if os.path.exists(report_path):
    result["report_exists"] = True
    if os.path.getmtime(report_path) > task_start:
        result["report_created_during_task"] = True
        
    with open(report_path, "r") as f:
        content = f.read().strip()
    result["report_content"] = content
    
    # Try to extract floating point number for c1
    # Matches simple decimals or scientific notation (e.g. -0.038, -3.8e-2)
    matches = re.findall(r'-?\d+\.\d+(?:e[+-]?\d+)?', content.lower())
    if matches:
        result["reported_c1"] = float(matches[0])

# Write result JSON safely
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Task Result JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="