#!/bin/bash
echo "=== Exporting Lysozyme SS Teaching Figure Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/lysozyme_ss_end_screenshot.png

# Use Python to safely package the results into a JSON file
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/lysozyme_ss_start_ts", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

fig_path = "/home/ga/PyMOL_Data/images/lysozyme_ss.png"
report_path = "/home/ga/PyMOL_Data/lysozyme_ss_report.txt"

result = {
    "task_start_ts": task_start
}

# Figure check
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_mtime"] = int(os.path.getmtime(fig_path))
    result["figure_is_new"] = result["figure_mtime"] > task_start
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

with open("/tmp/lysozyme_ss_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/lysozyme_ss_result.json")
PYEOF

echo "=== Export Complete ==="