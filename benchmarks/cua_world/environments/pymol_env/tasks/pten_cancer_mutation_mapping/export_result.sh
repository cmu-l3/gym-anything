#!/bin/bash
echo "=== Exporting PTEN Cancer Mutation Mapping Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/pten_mutation_end_screenshot.png

python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/pten_mutation_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/pten_mutations.png"
report_path = "/home/ga/PyMOL_Data/pten_mutation_report.txt"

result = {}

# Check for rendered figure
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Check for text report
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

with open("/tmp/pten_mutation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/pten_mutation_result.json")
PYEOF

echo "=== Export Complete ==="