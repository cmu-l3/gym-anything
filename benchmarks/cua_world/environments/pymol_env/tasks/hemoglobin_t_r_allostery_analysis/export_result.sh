#!/bin/bash
echo "=== Exporting Hemoglobin T/R Allostery Analysis Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/hemo_allostery_end_screenshot.png

python3 << 'PYEOF'
import json, os

TASK_START = int(open("/tmp/hemo_allostery_start_ts").read().strip())

fig_path = "/home/ga/PyMOL_Data/images/hemo_superposition.png"
report_path = "/home/ga/PyMOL_Data/hemo_rmsd_report.txt"

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
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

with open("/tmp/hemo_allostery_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/hemo_allostery_result.json")
PYEOF

echo "=== Export Complete ==="
