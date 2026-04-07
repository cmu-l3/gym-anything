#!/bin/bash
echo "=== Exporting hpv_integration_mapping results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/integration_mapping/results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Use Python to safely package the text file contents and check modification times
python3 << PYEOF
import json
import os
import re

result = {
    "gb_exists": False,
    "gb_created_during_task": False,
    "features_section": "",
    "report_exists": False,
    "report_created_during_task": False,
    "report_content": ""
}

task_start = int("${TASK_START}")
gb_path = "${RESULTS_DIR}/patient_annotated.gb"
report_path = "${RESULTS_DIR}/integration_report.txt"

# Export GenBank Data
if os.path.exists(gb_path):
    result["gb_exists"] = True
    mtime = int(os.path.getmtime(gb_path))
    if mtime > task_start:
        result["gb_created_during_task"] = True
        
    with open(gb_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        
    # Extract just the FEATURES section to avoid massive JSON
    features_match = re.search(r'FEATURES\s+Location/Qualifiers(.*?)(?:ORIGIN|$)', content, re.DOTALL)
    if features_match:
        result["features_section"] = features_match.group(1)

# Export Report Data
if os.path.exists(report_path):
    result["report_exists"] = True
    mtime = int(os.path.getmtime(report_path))
    if mtime > task_start:
        result["report_created_during_task"] = True
        
    with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
        result["report_content"] = f.read()

# Write output to tmp
with open('/tmp/hpv_integration_mapping_result.json', 'w') as f:
    json.dump(result, f)

PYEOF

chmod 666 /tmp/hpv_integration_mapping_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/hpv_integration_mapping_result.json."