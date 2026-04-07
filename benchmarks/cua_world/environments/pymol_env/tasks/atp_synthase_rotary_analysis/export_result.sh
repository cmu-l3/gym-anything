#!/bin/bash
echo "=== Exporting ATP Synthase Rotary Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification and debugging
take_screenshot /tmp/f1_rotary_end_screenshot.png

# Collect result data using Python heredoc to safely handle JSON parsing and text content
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/f1_rotary_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/atp_synthase_f1.png"
report_path = "/home/ga/PyMOL_Data/f1_rotary_report.txt"

result = {}

# Check the figure output
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Check the report output
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Save payload for the verifier
result_json_path = "/tmp/f1_rotary_result.json"
with open(result_json_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {result_json_path}")
PYEOF

echo "=== Export Complete ==="