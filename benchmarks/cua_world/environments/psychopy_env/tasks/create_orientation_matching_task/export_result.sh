#!/bin/bash
echo "=== Exporting create_orientation_matching_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess
import csv
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/orientation_matching.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions/oblique_targets.csv"
RESULT_FILE = "/tmp/task_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    "exp_exists": False,
    "cond_exists": False,
    "exp_valid_xml": False,
    "cond_valid_csv": False,
    "cond_columns": [],
    "cond_rows": 0,
    "has_code_component": False,
    "code_each_frame_content": "",
    "code_begin_routine_content": "",
    "grating_count": 0,
    "dynamic_orientation": False,
    "keyboard_end_routine": False
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

# Read nonce
try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# Check Conditions File
if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    try:
        with open(COND_FILE, 'r') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                results["cond_columns"] = [c.strip() for c in reader.fieldnames]
                rows = list(reader)
                results["cond_rows"] = len(rows)
                results["cond_valid_csv"] = True
    except Exception as e:
        print(f"CSV error: {e}")

# Check Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["exp_valid_xml"] = True
        
        # Analyze Components
        routines = root.findall(".//Routine")
        for routine in routines:
            # Check for Grating/Gabor stimuli
            gratings = []
            for comp in routine:
                if comp.tag in ["GratingComponent", "ImageComponent"]: # GratingComponent usually
                    gratings.append(comp)
            
            # If we find gratings, check properties
            if len(gratings) > 0:
                results["grating_count"] = max(results["grating_count"], len(gratings))
                for g in gratings:
                    for param in g:
                        # Check for dynamic orientation updates
                        if param.get("name") == "ori":
                            updates = param.get("updates", "")
                            val = param.get("val", "")
                            if updates == "set every frame" or "$" in val:
                                results["dynamic_orientation"] = True

            # Check Code Components
            for comp in routine:
                if comp.tag == "CodeComponent":
                    results["has_code_component"] = True
                    for param in comp:
                        if param.get("name") == "Each Frame":
                            results["code_each_frame_content"] = param.get("val", "")
                        if param.get("name") == "Begin Routine":
                            results["code_begin_routine_content"] = param.get("val", "")

            # Check Keyboard
            for comp in routine:
                if "Keyboard" in comp.tag or "Key" in comp.tag:
                    for param in comp:
                        if param.get("name") == "forceEndRoutine" and param.get("val") == "True":
                            results["keyboard_end_routine"] = True

    except Exception as e:
        print(f"XML error: {e}")

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="