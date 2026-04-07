#!/bin/bash
echo "=== Exporting Telomeric G-Quadruplex Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/g_quadruplex_end_screenshot.png

# Collect result data using Python heredoc to ensure clean JSON formatting
python3 << 'PYEOF'
import json
import os

# Safely read start timestamp
try:
    with open("/tmp/g_quadruplex_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/g_quadruplex.png"
report_path = "/home/ga/PyMOL_Data/k_coordination_report.txt"

result = {}

# Check PNG Figure
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Check Text Report
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Save to temp JSON result path
with open("/tmp/g_quadruplex_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/g_quadruplex_result.json")
PYEOF

echo "=== Export Complete ==="