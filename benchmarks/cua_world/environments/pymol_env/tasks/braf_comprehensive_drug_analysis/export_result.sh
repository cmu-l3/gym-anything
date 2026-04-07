#!/bin/bash
echo "=== Exporting BRAF Comprehensive Drug Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/braf_comprehensive_end_screenshot.png

# Collect all outputs into a single JSON for the verifier
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/braf_comprehensive_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

# Define all expected output paths
figure_paths = {
    "pocket":   "/home/ga/PyMOL_Data/images/braf_vemurafenib_pocket.png",
    "dfg":      "/home/ga/PyMOL_Data/images/braf_dfg_comparison.png",
    "surface":  "/home/ga/PyMOL_Data/images/braf_pocket_surface.png",
    "mutation":  "/home/ga/PyMOL_Data/images/braf_gatekeeper_mutation.png",
}
report_path  = "/home/ga/PyMOL_Data/braf_drug_analysis_report.txt"
session_path = "/home/ga/PyMOL_Data/sessions/braf_analysis.pse"

result = {"task_start_ts": TASK_START}

# --- Check each figure ---
result["figures"] = {}
for name, path in figure_paths.items():
    fig = {"exists": False, "size_bytes": 0, "is_new": False}
    if os.path.isfile(path):
        fig["exists"] = True
        fig["size_bytes"] = os.path.getsize(path)
        fig["is_new"] = int(os.path.getmtime(path)) > TASK_START
    result["figures"][name] = fig

# --- Check report ---
result["report"] = {"exists": False, "is_new": False, "content": "", "line_count": 0}
if os.path.isfile(report_path):
    result["report"]["exists"] = True
    result["report"]["is_new"] = int(os.path.getmtime(report_path)) > TASK_START
    with open(report_path, "r", errors="replace") as f:
        content = f.read()
    result["report"]["content"] = content
    result["report"]["line_count"] = len([l for l in content.splitlines() if l.strip()])

# --- Check session ---
result["session"] = {"exists": False}
if os.path.isfile(session_path):
    result["session"]["exists"] = True

# Write result JSON
output_json = "/tmp/braf_comprehensive_result.json"
with open(output_json, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(output_json, 0o666)
print(f"Result written to {output_json}")
PYEOF

echo "=== Export Complete ==="
