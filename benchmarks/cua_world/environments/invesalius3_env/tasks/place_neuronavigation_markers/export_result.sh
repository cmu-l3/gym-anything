#!/bin/bash
set -e
echo "=== Exporting place_neuronavigation_markers result ==="

source /workspace/scripts/task_utils.sh

# Paths
REPORT_PATH="/home/ga/Documents/fiducial_report.txt"
PROJECT_PATH="/home/ga/Documents/neuronavigation_plan.inv3"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Analyze Output Files using Python
# We do the parsing inside the container to avoid complex string manipulation in bash
python3 << PYEOF
import json
import os
import re
import tarfile

result = {
    "timestamp": "$(date -Iseconds)",
    "task_start_ts": $TASK_START,
    "report_exists": False,
    "report_created_during_task": False,
    "valid_marker_count": 0,
    "markers": [],
    "project_exists": False,
    "project_created_during_task": False,
    "project_valid_archive": False,
    "screenshot_exists": False
}

# --- Check Report File ---
report_path = "$REPORT_PATH"
if os.path.exists(report_path):
    result["report_exists"] = True
    mtime = os.path.getmtime(report_path)
    if mtime > result["task_start_ts"]:
        result["report_created_during_task"] = True
    
    # Parse content
    try:
        with open(report_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                # Expected format: Name: X, Y, Z (flexible separators)
                # Regex to capture name and 3 floats
                match = re.search(r'^([^:]+?)[:\s]+([-+]?\d*\.?\d+)[,\s]+([-+]?\d*\.?\d+)[,\s]+([-+]?\d*\.?\d+)', line)
                if match:
                    name = match.group(1).strip()
                    x, y, z = float(match.group(2)), float(match.group(3)), float(match.group(4))
                    result["markers"].append({"name": name, "x": x, "y": y, "z": z})
        result["valid_marker_count"] = len(result["markers"])
    except Exception as e:
        result["report_error"] = str(e)

# --- Check Project File ---
project_path = "$PROJECT_PATH"
if os.path.exists(project_path):
    result["project_exists"] = True
    mtime = os.path.getmtime(project_path)
    if mtime > result["task_start_ts"]:
        result["project_created_during_task"] = True
    
    # Check if valid tar
    try:
        if tarfile.is_tarfile(project_path):
            result["project_valid_archive"] = True
    except:
        pass

# --- Check Screenshot ---
if os.path.exists("/tmp/task_final.png"):
    result["screenshot_exists"] = True

# Output to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete. Found markers:", result["valid_marker_count"])
PYEOF

# 3. Secure output permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json