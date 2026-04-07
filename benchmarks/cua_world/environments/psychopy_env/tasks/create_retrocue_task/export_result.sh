#!/bin/bash
echo "=== Exporting create_retrocue_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Run Python analysis script inside the container
python3 << 'PYEOF'
import json
import os
import sys
import csv
import glob
import xml.etree.ElementTree as ET
import datetime

EXP_FILE = "/home/ga/PsychoPyExperiments/retrocue/retrocue_task.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/retrocue/conditions.csv"
DATA_DIR = "/home/ga/PsychoPyExperiments/retrocue/data"
RESULT_FILE = "/tmp/retrocue_result.json"

results = {
    "exp_exists": False,
    "cond_exists": False,
    "data_exists": False,
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    # Condition File Checks
    "cond_columns_valid": False,
    "cond_row_count": 0,
    "cond_logic_score": 0, # How many rows have correct logic
    # Experiment Structure Checks
    "routines_found": [],
    "has_loop": False,
    "components_linked": False, # Checks if variables like $left_color are used
    "psyexp_valid_xml": False
}

# Read start time and nonce
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except: pass

try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except: pass

# 1. Check Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["psyexp_valid_xml"] = True
        
        # Check Routines
        routines = root.findall(".//Routine")
        found_routines = [r.get("name") for r in routines]
        results["routines_found"] = found_routines
        
        # Check Components for Variable Linking
        # Look for Polygon with fillColor=$left_color or similar
        linked_count = 0
        for comp in root.findall(".//Component"):
            for param in comp.findall("Param"):
                val = param.get("val", "")
                if "$" in val and ("left_color" in val or "right_color" in val or "cue_dir" in val):
                    linked_count += 1
        if linked_count >= 2:
            results["components_linked"] = True
            
        # Check Loop
        if root.findall(".//LoopInitiator"):
            results["has_loop"] = True
            
    except Exception as e:
        print(f"XML Error: {e}")

# 2. Check Conditions File
if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    try:
        with open(COND_FILE, 'r') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                req_cols = {"left_color", "right_color", "cue_dir", "probe_color", "corr_resp"}
                if req_cols.issubset(set(reader.fieldnames)):
                    results["cond_columns_valid"] = True
            
            rows = list(reader)
            results["cond_row_count"] = len(rows)
            
            # Check Logic
            correct_logic_rows = 0
            for row in rows:
                try:
                    cue = row['cue_dir'].lower()
                    probe = row['probe_color'].lower()
                    left = row['left_color'].lower()
                    right = row['right_color'].lower()
                    resp = row['corr_resp'].lower()
                    
                    target_color = left if 'left' in cue else right
                    expected = 'y' if probe == target_color else 'n'
                    
                    if resp == expected:
                        correct_logic_rows += 1
                except: pass
            results["cond_logic_score"] = correct_logic_rows
            
    except Exception as e:
        print(f"CSV Error: {e}")

# 3. Check Data Generation
if os.path.isdir(DATA_DIR):
    # Find any .csv or .psydat file created after start time
    data_files = glob.glob(os.path.join(DATA_DIR, "*"))
    for df in data_files:
        if os.path.getmtime(df) > results["task_start_time"]:
            results["data_exists"] = True
            break

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
os.chmod(RESULT_FILE, 0o666)
PYEOF

echo "Result JSON generated at /tmp/retrocue_result.json"
cat /tmp/retrocue_result.json
echo "=== Export complete ==="