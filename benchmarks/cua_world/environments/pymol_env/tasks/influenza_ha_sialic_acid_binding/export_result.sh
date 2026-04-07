#!/bin/bash
echo "=== Exporting Influenza HA Sialic Acid Binding Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/ha_sialic_acid_end_screenshot.png

# Safely extract file properties and JSON using python heredoc pattern
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/ha_sialic_acid_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/ha_receptor_binding.png"
report_path = "/home/ga/PyMOL_Data/ha_sialic_acid_contacts.txt"

result = {}

# Assess Figure
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Assess Report
if os.path.isfile(report_path):
    result["report_exists"] = True
    result["report_is_new"] = int(os.path.getmtime(report_path)) > TASK_START
    try:
        with open(report_path, "r", errors="replace") as f:
            result["report_content"] = f.read()
    except Exception:
        result["report_content"] = ""
else:
    result["report_exists"] = False
    result["report_is_new"] = False
    result["report_content"] = ""

# Write to robust intermediate
with open("/tmp/ha_sialic_acid_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/ha_sialic_acid_result.json")
PYEOF

echo "=== Export Complete ==="