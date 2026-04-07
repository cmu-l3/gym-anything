#!/bin/bash
echo "=== Exporting GFP Chromophore Environment Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot to capture final application state
take_screenshot /tmp/gfp_chromophore_end_screenshot.png

# Run Python inside container to securely evaluate files and output a JSON result
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/gfp_chromophore_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/gfp_chromophore.png"
report_path = "/home/ga/PyMOL_Data/gfp_environment_report.txt"

result = {}

# Check Image Output
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    # Check if the file's modified time is strictly after the task started
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Check Text Report Output
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

with open("/tmp/gfp_chromophore_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/gfp_chromophore_result.json")
PYEOF

echo "=== Export Complete ==="