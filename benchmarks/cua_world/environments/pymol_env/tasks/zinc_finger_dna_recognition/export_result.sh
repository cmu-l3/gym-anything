#!/bin/bash
echo "=== Exporting Zinc Finger DNA Recognition Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/zif268_end_screenshot.png

# Collect file data and create JSON
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/zif268_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/zif268_finger2.png"
report_path = "/home/ga/PyMOL_Data/zif268_report.txt"

result = {}

# Check figure
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    # Anti-gaming: Ensure file was modified after the task started
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Check report
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Save payload securely
with open("/tmp/zif268_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result successfully written to /tmp/zif268_result.json")
PYEOF

echo "=== Export Complete ==="