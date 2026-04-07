#!/bin/bash
echo "=== Exporting SOD1 Electrostatic Funnel Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/sod1_electrostatic_end_screenshot.png

# Collect result data using Python heredoc for robust JSON generation
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/sod1_electrostatic_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/sod1_electrostatic.png"
report_path = "/home/ga/PyMOL_Data/sod1_electrostatic_report.txt"

result = {}

# Figure check
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    # Check if modified/created after task start
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

# Write to a temporary file then move, to avoid partial reads
tmp_out = "/tmp/sod1_electrostatic_result_tmp.json"
final_out = "/tmp/sod1_electrostatic_result.json"

with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

os.replace(tmp_out, final_out)
os.chmod(final_out, 0o666)

print(f"Result written to {final_out}")
PYEOF

echo "=== Export Complete ==="