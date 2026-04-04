#!/bin/bash
echo "=== Exporting document_cranial_dimensions result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# Paths
REPORT_PATH="/home/ga/Documents/cranial_report.txt"
PROJECT_PATH="/home/ga/Documents/forensic_cranium.inv3"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to parse files and validate content safely
python3 << PYEOF
import json
import os
import re
import tarfile
import plistlib
import sys

result = {
    "report_exists": False,
    "report_created_during_task": False,
    "extracted_values": [],
    "project_exists": False,
    "project_created_during_task": False,
    "project_valid_inv3": False,
    "measurement_count": 0,
    "error": None
}

report_path = "$REPORT_PATH"
project_path = "$PROJECT_PATH"
task_start = int("$TASK_START")

try:
    # 1. Analyze Text Report
    if os.path.exists(report_path):
        result["report_exists"] = True
        mtime = os.path.getmtime(report_path)
        if mtime > task_start:
            result["report_created_during_task"] = True
        
        # Extract numbers using regex (looking for floats like 180.5, 145, etc.)
        try:
            with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                # Find all numbers that might be dimensions (integers or floats)
                # Matches: 123, 123.45
                matches = re.findall(r"[-+]?\d*\.\d+|\d+", content)
                # Filter to valid floats
                values = []
                for m in matches:
                    try:
                        val = float(m)
                        values.append(val)
                    except ValueError:
                        continue
                result["extracted_values"] = values
        except Exception as e:
            result["error"] = f"Error reading report: {str(e)}"

    # 2. Analyze Project File (.inv3 is a tar.gz)
    if os.path.exists(project_path):
        result["project_exists"] = True
        mtime = os.path.getmtime(project_path)
        if mtime > task_start:
            result["project_created_during_task"] = True
            
        try:
            if tarfile.is_tarfile(project_path):
                with tarfile.open(project_path, "r:*") as tar:
                    # Look for measurements.plist
                    try:
                        f = tar.extractfile("measurements.plist")
                        if f:
                            pl = plistlib.load(f)
                            # InVesalius stores measurements as a dict or list in plist
                            result["measurement_count"] = len(pl)
                            result["project_valid_inv3"] = True
                        else:
                            # Valid tar, but no measurements file
                            result["project_valid_inv3"] = True
                            result["measurement_count"] = 0
                    except KeyError:
                        # File not found in tar
                        result["project_valid_inv3"] = True
                        result["measurement_count"] = 0
            else:
                 result["error"] = "Project file is not a valid tar archive"
        except Exception as e:
            result["error"] = f"Error parsing project: {str(e)}"

except Exception as e:
    result["error"] = str(e)

# Write result to temp file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)

print(json.dumps(result, indent=4))
PYEOF

# Ensure permissions for copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="