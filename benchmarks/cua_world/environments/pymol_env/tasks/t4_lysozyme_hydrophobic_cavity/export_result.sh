#!/bin/bash
echo "=== Exporting T4 Lysozyme Hydrophobic Cavity Result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/t4_cavity_end_screenshot.png

# Collect file data and create verification JSON payload using Python
python3 << 'PYEOF'
import json
import os

# Safely read the start timestamp
try:
    with open("/tmp/t4_cavity_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/t4_cavity_superposition.png"
report_path = "/home/ga/PyMOL_Data/t4_cavity_report.txt"

result = {}

# Evaluate the figure image file
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    # File must be modified/created after the task start time
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Evaluate the report text file
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Output the results to a temporary JSON for the verifier
with open("/tmp/t4_cavity_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/t4_cavity_result.json")
PYEOF

echo "=== Export Complete ==="