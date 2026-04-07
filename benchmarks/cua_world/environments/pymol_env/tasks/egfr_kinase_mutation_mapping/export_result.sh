#!/bin/bash
echo "=== Exporting EGFR Kinase Mutation Mapping Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Collect result data using Python heredoc for robust JSON generation
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/egfr_mutations.png"
report_path = "/home/ga/PyMOL_Data/egfr_report.txt"

result = {
    "task_start_time": TASK_START
}

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
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

with open("/tmp/egfr_task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/egfr_task_result.json")
PYEOF

echo "=== Export Complete ==="