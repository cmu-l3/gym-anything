#!/bin/bash
echo "=== Exporting Collagen Triple Helix Packing Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for trajectory/evidence
take_screenshot /tmp/collagen_end_screenshot.png

# Collect result data using Python heredoc for robust JSON generation
python3 << 'PYEOF'
import json, os

# Read the start timestamp generated in setup_task.sh
try:
    with open("/tmp/collagen_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/collagen_core.png"
report_path = "/home/ga/PyMOL_Data/collagen_report.txt"

result = {}

# Check Image Output
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    # Validate the file was created AFTER the task started
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Check Text Report Output
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Export to a JSON file for the verifier to read
with open("/tmp/collagen_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/collagen_result.json")
PYEOF

echo "=== Export Complete ==="