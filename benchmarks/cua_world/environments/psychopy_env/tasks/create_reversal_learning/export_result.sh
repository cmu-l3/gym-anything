#!/bin/bash
echo "=== Exporting Reversal Learning Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Run analysis script
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import subprocess
import xml.etree.ElementTree as ET
import re

EXP_FILE = "/home/ga/PsychoPyExperiments/reversal_learning.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions/spatial_positions.csv"
RESULT_FILE = "/tmp/reversal_learning_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    # File Existence
    "exp_exists": False,
    "cond_exists": False,
    "exp_modified": False,
    "cond_modified": False,
    # CSV Analysis
    "csv_rows": 0,
    "csv_cols": [],
    "csv_balanced": False,
    "csv_has_colors": False,
    # Experiment Structure
    "has_routines": False,
    "has_loop": False,
    "loop_uses_csv": False,
    "has_mouse": False,
    "has_code_component": False,
    # Code Logic Analysis
    "code_uses_random": False,
    "code_checks_criterion": False, # Checks for '8'
    "code_logs_data": False,        # Checks for addData
    "code_logic_score": 0           # Heuristic score
}

# Read task metadata
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# Analyze CSV
if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    if os.path.getmtime(COND_FILE) > results["task_start_time"]:
        results["cond_modified"] = True
    
    try:
        with open(COND_FILE, 'r') as f:
            reader = csv.DictReader(f)
            results["csv_cols"] = reader.fieldnames if reader.fieldnames else []
            rows = list(reader)
            results["csv_rows"] = len(rows)
            
            # Check balance
            left_orange = sum(1 for r in rows if 'orange' in r.get('left_color', '').lower())
            left_blue = sum(1 for r in rows if 'blue' in r.get('left_color', '').lower())
            
            # Allow slight imbalance if total rows are weird, but target is 20/20
            if abs(left_orange - left_blue) <= 2 and results["csv_rows"] >= 10:
                results["csv_balanced"] = True
                
            if 'left_color' in results["csv_cols"] and 'right_color' in results["csv_cols"]:
                results["csv_has_colors"] = True
    except Exception as e:
        print(f"CSV Error: {e}")

# Analyze Experiment XML
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    if os.path.getmtime(EXP_FILE) > results["task_start_time"]:
        results["exp_modified"] = True
        
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        
        # Check Routines
        routines = [r.get('name') for r in root.findall(".//Routine")]
        if 'instructions' in routines and 'trial' in routines and 'feedback' in routines:
            results["has_routines"] = True
            
        # Check Loop
        loops = root.findall(".//LoopInitiator")
        if loops:
            results["has_loop"] = True
            for loop in loops:
                param = loop.find(".//Param[@name='conditionsFile']")
                if param is not None and "spatial_positions.csv" in param.get('val', ''):
                    results["loop_uses_csv"] = True
                    
        # Check Components in Trial Routine
        trial_routine = root.find(".//Routine[@name='trial']")
        if trial_routine:
            for comp in trial_routine:
                if 'Mouse' in comp.tag:
                    results["has_mouse"] = True
        
        # Check Code Component (can be anywhere, likely in trial or code routine)
        code_comps = root.findall(".//CodeComponent")
        if code_comps:
            results["has_code_component"] = True
            
            # Aggregate all code text for analysis
            all_code = ""
            for cc in code_comps:
                for param in cc:
                    if param.get('name') in ['Begin Experiment', 'Begin Routine', 'End Routine', 'Each Frame']:
                        all_code += (param.get('val') or "") + "\n"
            
            # Heuristic Logic Analysis
            if re.search(r'random|randint|uniform|shuffle', all_code):
                results["code_uses_random"] = True
                results["code_logic_score"] += 1
            
            # Check for reversal criterion (8) and logging
            if '8' in all_code and ('if' in all_code or '==' in all_code):
                results["code_checks_criterion"] = True
                results["code_logic_score"] += 1
                
            if 'addData' in all_code:
                results["code_logs_data"] = True
                results["code_logic_score"] += 1
                
            if 'win_outcome' in all_code or 'current_target' in all_code:
                results["code_logic_score"] += 1

    except Exception as e:
        print(f"XML Error: {e}")

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
PYEOF

echo "Analysis complete. JSON saved."