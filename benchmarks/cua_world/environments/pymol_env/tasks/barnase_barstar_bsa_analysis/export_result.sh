#!/bin/bash
echo "=== Exporting Barnase-Barstar BSA Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/barnase_bsa_end_screenshot.png

# Collect result data using Python
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/barnase_bsa_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/barnase_footprint.png"
report_path = "/home/ga/PyMOL_Data/bsa_report.txt"

result = {}

# Figure check
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Report check
if os.path.isfile(report_path):
    result["report_exists"] = True
    result["report_is_new"] = int(os.path.getmtime(report_path)) > TASK_START
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_is_new"] = False
    result["report_content"] = ""

with open("/tmp/barnase_bsa_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/barnase_bsa_result.json")
PYEOF

echo "=== Export Complete ==="