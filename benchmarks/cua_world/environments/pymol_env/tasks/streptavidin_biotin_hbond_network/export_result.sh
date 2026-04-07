#!/bin/bash
echo "=== Exporting Streptavidin-Biotin H-bond Network Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/1stp_end_screenshot.png

# Collect result data using Python heredoc for robust JSON generation
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/1stp_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/streptavidin_hbond.png"
report_path = "/home/ga/PyMOL_Data/biotin_hbond_report.txt"

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

# Write to temp file then move to avoid partial writes
with open("/tmp/1stp_hbond_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)

os.replace("/tmp/1stp_hbond_result_tmp.json", "/tmp/1stp_hbond_result.json")
os.chmod("/tmp/1stp_hbond_result.json", 0o666)

print("Result written to /tmp/1stp_hbond_result.json")
PYEOF

echo "=== Export Complete ==="