#!/bin/bash
echo "=== Exporting p53 DNA Hotspot Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/p53_task_end_screenshot.png

# Collect result data using Python heredoc for robust JSON generation
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/p53_task_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/p53_dna_hotspots.png"
report_path = "/home/ga/PyMOL_Data/p53_hotspot_report.txt"

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
    try:
        with open(report_path, "r", errors="replace") as f:
            result["report_content"] = f.read()
    except Exception as e:
        result["report_content"] = f"Error reading report: {str(e)}"
else:
    result["report_exists"] = False
    result["report_content"] = ""

with open("/tmp/p53_hotspot_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/p53_hotspot_result.json")
PYEOF

echo "=== Export Complete ==="