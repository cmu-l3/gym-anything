#!/bin/bash
echo "=== Exporting GroEL Chamber Expansion Result ==="

source /workspace/scripts/task_utils.sh

# Take final evidence screenshot
take_screenshot /tmp/groel_end_screenshot.png

# Collect result data robustly using Python heredoc
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/groel_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/groel_chamber_sliced.png"
report_path = "/home/ga/PyMOL_Data/groel_report.txt"

result = {}

# Assess the exported figure
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    # Check that figure was created AFTER the task began
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Read the structural report
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Dump to temp JSON for verifier.py
with open("/tmp/groel_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/groel_result.json")
PYEOF

echo "=== Export Complete ==="