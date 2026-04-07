#!/bin/bash
echo "=== Exporting Antibody-Antigen Interface Mapping Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/dvf_interface_end_screenshot.png

python3 << 'PYEOF'
import json, os

TASK_START = int(open("/tmp/dvf_interface_start_ts").read().strip())

fig_path = "/home/ga/PyMOL_Data/images/dvf_interface.png"
report_path = "/home/ga/PyMOL_Data/dvf_interface_report.txt"

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

with open("/tmp/dvf_interface_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/dvf_interface_result.json")
PYEOF

echo "=== Export Complete ==="
