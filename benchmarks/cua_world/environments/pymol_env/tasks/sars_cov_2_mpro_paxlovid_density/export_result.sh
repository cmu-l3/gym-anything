#!/bin/bash
echo "=== Exporting Paxlovid Electron Density Result ==="

source /workspace/scripts/task_utils.sh

# Take final evidence screenshot
take_screenshot /tmp/paxlovid_density_end_screenshot.png

# Collect result data using Python heredoc to safely handle text content
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/paxlovid_density_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/paxlovid_density.png"
report_path = "/home/ga/PyMOL_Data/paxlovid_density_report.txt"

result = {}

# Output Figure evaluation
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Report content extraction
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Write to container /tmp for verifier reading
with open("/tmp/paxlovid_density_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/paxlovid_density_result.json")
PYEOF

echo "=== Export Complete ==="