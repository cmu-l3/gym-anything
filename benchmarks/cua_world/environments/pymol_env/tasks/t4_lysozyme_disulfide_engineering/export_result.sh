#!/bin/bash
echo "=== Exporting T4 Lysozyme Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot showing end state
take_screenshot /tmp/t4l_end_screenshot.png

# Collect result data using Python heredoc for safe JSON serialization
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/t4l_task_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/t4l_engineered_disulfide.png"
report_path = "/home/ga/PyMOL_Data/t4l_disulfide_report.txt"

result = {}

# Evaluate figure creation and timestamp
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    # Ensure the file was generated *after* the task started
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Evaluate text report
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

with open("/tmp/t4l_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result successfully written to /tmp/t4l_result.json")
PYEOF

echo "=== Export Complete ==="