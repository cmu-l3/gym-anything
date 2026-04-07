#!/bin/bash
echo "=== Exporting Ubiquitin Lysine SASA Mapping Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/ubq_lysine_end_screenshot.png

# Collect result data using Python heredoc for robust JSON generation
python3 << 'PYEOF'
import json, os

TASK_START = int(open("/tmp/ubq_lysine_start_ts").read().strip())

fig_path = "/home/ga/PyMOL_Data/images/ubq_lysines.png"
report_path = "/home/ga/PyMOL_Data/ubiquitin_lysine_report.txt"

result = {}

# Figure check
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    # Check if the file is newer than task start
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

with open("/tmp/ubq_lysine_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/ubq_lysine_result.json")
PYEOF

echo "=== Export Complete ==="