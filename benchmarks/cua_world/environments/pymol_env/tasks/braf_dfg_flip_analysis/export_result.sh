#!/bin/bash
echo "=== Exporting BRAF DFG-Flip Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Capture the final state visible to the agent
take_screenshot /tmp/braf_dfg_end_screenshot.png

# Package outputs into JSON format for the verifier using Python
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/braf_dfg_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/braf_dfg_flip.png"
report_path = "/home/ga/PyMOL_Data/braf_inhibition_report.txt"

result = {}

# Check Image Output
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
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

# Write to standardized file for verifier consumption
with open("/tmp/braf_dfg_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result successfully written to /tmp/braf_dfg_result.json")
PYEOF

echo "=== Export Complete ==="