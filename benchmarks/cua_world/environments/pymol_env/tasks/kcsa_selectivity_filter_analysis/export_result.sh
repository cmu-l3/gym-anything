#!/bin/bash
echo "=== Exporting KcsA Selectivity Filter Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Capture the final screen state
take_screenshot /tmp/kcsa_end_screenshot.png

# Extract properties via Python to handle JSON safely and parse cleanly
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/kcsa_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/kcsa_selectivity_filter.png"
report_path = "/home/ga/PyMOL_Data/kcsa_filter_report.txt"

result = {}

# Evaluate the visual figure
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    # Important anti-gaming check: File modified after task began
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Read report content
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

with open("/tmp/kcsa_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/kcsa_result.json")
PYEOF

echo "=== Export Complete ==="