#!/bin/bash
echo "=== Exporting Insulin Crystal Packing Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/insulin_crystal_end_screenshot.png

# Collect result data using Python heredoc for robust JSON generation
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/insulin_crystal_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/insulin_packing.png"
report_path = "/home/ga/PyMOL_Data/insulin_crystal_report.txt"

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

# Write to temp file then move to ensure permissions
tmp_path = "/tmp/result_tmp.json"
with open(tmp_path, "w") as f:
    json.dump(result, f, indent=2)

os.system(f"mv {tmp_path} /tmp/insulin_crystal_result.json")
os.system("chmod 666 /tmp/insulin_crystal_result.json 2>/dev/null || true")

print("Result written to /tmp/insulin_crystal_result.json")
PYEOF

echo "=== Export Complete ==="