#!/bin/bash
echo "=== Exporting DNA Anthracycline Intercalation Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual evidence
take_screenshot /tmp/dna_intercalation_end_screenshot.png

# Collect result data using Python heredoc for robust JSON generation
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/dna_intercalation_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/dna_intercalation.png"
report_path = "/home/ga/PyMOL_Data/intercalation_report.txt"

result = {}

# Check Image Output
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Check Report Output
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Write JSON for verifier.py
with open("/tmp/dna_intercalation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/dna_intercalation_result.json")
PYEOF

echo "=== Export Complete ==="