#!/bin/bash
echo "=== Exporting Ferritin Nanocage Assembly Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM / debugging
take_screenshot /tmp/ferritin_end_screenshot.png

# Safely extract verification data into a JSON using a Python heredoc
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/ferritin_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/ferritin_cage.png"
report_path = "/home/ga/PyMOL_Data/ferritin_analysis_report.txt"

result = {}

# Verify Figure exists, is sizable, and was created/modified during the task
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Extract the report content for evaluation
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

try:
    with open("/tmp/ferritin_result.json", "w") as f:
        json.dump(result, f, indent=2)
    print("Result written to /tmp/ferritin_result.json")
except Exception as e:
    print(f"Failed to write json: {e}")
PYEOF

echo "=== Export Complete ==="