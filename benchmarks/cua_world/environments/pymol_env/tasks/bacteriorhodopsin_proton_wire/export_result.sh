#!/bin/bash
echo "=== Exporting Bacteriorhodopsin Proton Wire Analysis Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/br_pathway_end_screenshot.png

# Collect result data using Python heredoc for robust JSON generation
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/br_pathway_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/br_proton_wire.png"
report_path = "/home/ga/PyMOL_Data/br_pathway_report.txt"

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

with open("/tmp/br_pathway_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/br_pathway_result.json")
PYEOF

echo "=== Export Complete ==="