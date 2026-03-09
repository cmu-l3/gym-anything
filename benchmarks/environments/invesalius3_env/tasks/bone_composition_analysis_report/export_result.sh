#!/bin/bash
set -e
echo "=== Exporting bone_composition_analysis_report result ==="

source /workspace/scripts/task_utils.sh

# Record end time and screenshot
TASK_END=$(date +%s)
take_screenshot /tmp/task_final.png

# Paths
PROJECT_FILE="/home/ga/Documents/bone_analysis.inv3"
REPORT_FILE="/home/ga/Documents/bone_report.txt"
RESULT_JSON="/tmp/task_result.json"

# Python script to analyze the artifacts inside the container
python3 << 'PYEOF'
import tarfile
import plistlib
import os
import json
import re

project_path = "/home/ga/Documents/bone_analysis.inv3"
report_path = "/home/ga/Documents/bone_report.txt"
start_time_path = "/tmp/task_start_time.txt"

result = {
    "project_exists": False,
    "project_valid": False,
    "report_exists": False,
    "masks": [],
    "report_content": "",
    "extracted_volumes": {},
    "file_timestamps_valid": False
}

# 1. Check Timestamps
try:
    with open(start_time_path, 'r') as f:
        start_time = int(f.read().strip())
    
    p_time = os.path.getmtime(project_path) if os.path.exists(project_path) else 0
    r_time = os.path.getmtime(report_path) if os.path.exists(report_path) else 0
    
    if p_time > start_time and r_time > start_time:
        result["file_timestamps_valid"] = True
except Exception:
    pass

# 2. Analyze Project File (.inv3 is a tar.gz containing plists)
if os.path.exists(project_path):
    result["project_exists"] = True
    try:
        with tarfile.open(project_path, "r:gz") as t:
            for member in t.getmembers():
                if member.name.startswith("mask_") and member.name.endswith(".plist"):
                    f = t.extractfile(member)
                    mask_data = plistlib.load(f)
                    thresh = mask_data.get("threshold_range", [0, 0])
                    result["masks"].append({
                        "name": mask_data.get("name", "Unknown"),
                        "threshold_min": thresh[0],
                        "threshold_max": thresh[1]
                    })
            result["project_valid"] = True
    except Exception as e:
        result["project_error"] = str(e)

# 3. Analyze Report File
if os.path.exists(report_path):
    result["report_exists"] = True
    try:
        with open(report_path, "r", errors="replace") as f:
            content = f.read()
            result["report_content"] = content
            
            # Extract numbers
            # Look for lines like "Compact Bone Volume: 123.45 mL"
            compact_match = re.search(r"Compact.*?(\d+\.?\d*)", content, re.IGNORECASE)
            spongial_match = re.search(r"Spongial.*?(\d+\.?\d*)", content, re.IGNORECASE)
            ratio_match = re.search(r"Ratio.*?(\d+\.?\d*)", content, re.IGNORECASE)
            
            if compact_match:
                result["extracted_volumes"]["compact"] = float(compact_match.group(1))
            if spongial_match:
                result["extracted_volumes"]["spongial"] = float(spongial_match.group(1))
            if ratio_match:
                result["extracted_volumes"]["ratio"] = float(ratio_match.group(1))
                
    except Exception as e:
        result["report_error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# Ensure permissions for copy_from_env
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Result JSON generated at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="