#!/bin/bash
echo "=== Exporting Ubiquitin NMR Ensemble Flexibility Result ==="

source /workspace/scripts/task_utils.sh

# Take final evidence screenshot
take_screenshot /tmp/ubq_nmr_end_screenshot.png

# Collect result data using Python heredoc for robust JSON formatting
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/ubq_nmr_start_ts") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/ubiquitin_ensemble.png"
report_path = "/home/ga/PyMOL_Data/ubiquitin_flexibility_report.txt"

result = {}

# Output Figure Check
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Written Report Check
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Write to tmp location for verifier execution
with open("/tmp/ubq_nmr_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result successfully written to /tmp/ubq_nmr_result.json")
PYEOF

echo "=== Export Complete ==="