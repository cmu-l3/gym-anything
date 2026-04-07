#!/bin/bash
echo "=== Exporting Calmodulin Contact Network Analysis Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/calmodulin_end_screenshot.png

python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/task_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/calmodulin_domains.png"
report_path = "/home/ga/PyMOL_Data/calmodulin_domain_report.txt"
contacts_path = "/home/ga/PyMOL_Data/calmodulin_contacts.txt"

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

# Contacts list check
if os.path.isfile(contacts_path):
    result["contacts_exists"] = True
    with open(contacts_path, "r", errors="replace") as f:
        # Read up to 5000 lines to prevent memory explosion if agent printed too much
        lines = f.readlines()[:5000]
        result["contacts_content"] = "".join(lines)
else:
    result["contacts_exists"] = False
    result["contacts_content"] = ""

with open("/tmp/calmodulin_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/calmodulin_result.json")
PYEOF

echo "=== Export Complete ==="