#!/bin/bash
echo "=== Exporting create_visuomotor_rotation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Paths
EXP_FILE="/home/ga/PsychoPyExperiments/motor_task/rotation_task.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/motor_task/targets.csv"
RESULT_FILE="/tmp/task_result.json"

# Python script to analyze the files in the container
python3 << 'PYEOF'
import json
import os
import sys
import csv
import math
import datetime
import subprocess

# Inputs
exp_path = "/home/ga/PsychoPyExperiments/motor_task/rotation_task.psyexp"
csv_path = "/home/ga/PsychoPyExperiments/motor_task/targets.csv"
output_json = "/tmp/task_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    "psychopy_running": False,
    
    # File Existence
    "exp_exists": False,
    "csv_exists": False,
    "exp_modified": False,
    "csv_modified": False,
    
    # CSV Analysis
    "csv_row_count": 0,
    "csv_columns": [],
    "csv_has_coordinates": False,
    
    # Experiment Analysis
    "is_valid_xml": False,
    "has_mouse": False,
    "has_code_component": False,
    "has_loop": False,
    "code_hides_mouse": False,
    "code_has_rotation_math": False,
    "code_sets_position": False,
    "visual_stim_count": 0
}

# 1. Basic checks (Timestamps, Nonce, Process)
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

# 2. CSV Analysis
if os.path.isfile(csv_path):
    results["csv_exists"] = True
    if os.path.getmtime(csv_path) > results["task_start_time"]:
        results["csv_modified"] = True
        
    try:
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
            if rows:
                results["csv_columns"] = [c.lower() for c in rows[0]]
                results["csv_row_count"] = len(rows) - 1 # exclude header
                
                # Check for coordinate-like data
                content = "".join([str(r) for r in rows]).lower()
                if "x" in results["csv_columns"] or "pos" in content:
                    results["csv_has_coordinates"] = True
    except:
        pass

# 3. Experiment Analysis (XML Parsing)
if os.path.isfile(exp_path):
    results["exp_exists"] = True
    if os.path.getmtime(exp_path) > results["task_start_time"]:
        results["exp_modified"] = True
        
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(exp_path)
        root = tree.getroot()
        
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True
            
        # Analyze Routines and Components
        routines = root.findall(".//Routine")
        for routine in routines:
            for comp in routine:
                ctype = comp.tag
                cname = comp.get("name", "")
                
                # Check Mouse
                if "Mouse" in ctype:
                    results["has_mouse"] = True
                    
                # Check Visual Stimuli (Polygon, Image, etc acting as cursor/targets)
                if "Polygon" in ctype or "Image" in ctype or "Text" in ctype:
                    results["visual_stim_count"] += 1
                    
                # Check Code Component
                if "Code" in ctype:
                    results["has_code_component"] = True
                    
                    # Check code content (Begin Routine, Each Frame, etc)
                    # We look for params named 'Begin Routine', 'Each Frame', etc.
                    code_content = ""
                    for param in comp:
                        val = param.get("val", "")
                        code_content += val + "\n"
                        
                    code_lower = code_content.lower()
                    
                    # Logic checks
                    if "mousevisible" in code_lower and "false" in code_lower:
                        results["code_hides_mouse"] = True
                        
                    # Rotation math keywords
                    if ("sin" in code_lower and "cos" in code_lower) or "rotation" in code_lower:
                         results["code_has_rotation_math"] = True
                         
                    # Setting position
                    if ".pos =" in code_lower or "setpos" in code_lower:
                        results["code_sets_position"] = True

        # Check Loops
        loops = root.findall(".//LoopInitiator")
        if len(loops) > 0:
            results["has_loop"] = True

    except Exception as e:
        print(f"XML Parse Error: {e}", file=sys.stderr)

# Save results
with open(output_json, 'w') as f:
    json.dump(results, f, indent=2)

os.chmod(output_json, 0o666)
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="