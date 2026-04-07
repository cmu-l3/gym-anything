#!/bin/bash
echo "=== Exporting create_flanker_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Run Python analysis script to generate result JSON
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import subprocess
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/flanker_task.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions/flanker_conditions.csv"
RESULT_FILE = "/tmp/create_flanker_task_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    # CSV Analysis
    "cond_file_exists": False,
    "cond_file_modified": False,
    "cond_columns": [],
    "cond_row_count": 0,
    "cond_has_congruent": False,
    "cond_has_incongruent": False,
    "cond_logic_valid": True, # Assume true until proven false
    "cond_logic_errors": [],
    # XML Analysis
    "exp_file_exists": False,
    "exp_file_modified": False,
    "exp_is_valid_xml": False,
    "exp_has_instructions": False,
    "exp_has_trial": False,
    "exp_has_loop": False,
    "exp_loop_nreps": 0,
    "exp_loop_file_ref": "",
    "exp_text_uses_var": False,
    "exp_kb_uses_var": False,
    "exp_kb_allowed_keys": "",
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

# --- Analyze Conditions CSV ---
if os.path.isfile(COND_FILE):
    results["cond_file_exists"] = True
    mtime = int(os.path.getmtime(COND_FILE))
    if mtime > results["task_start_time"]:
        results["cond_file_modified"] = True
    
    try:
        with open(COND_FILE, 'r', newline='') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                results["cond_columns"] = [c.lower().strip() for c in reader.fieldnames]
            
            rows = list(reader)
            results["cond_row_count"] = len(rows)
            
            for i, row in enumerate(rows):
                # Normalize keys
                r = {k.lower().strip(): v.strip() for k, v in row.items() if k}
                
                stim = r.get('stimulus', '')
                cond = r.get('condition', '').lower()
                corr = r.get('corrans', r.get('correctans', '')).lower()
                
                # Check condition types
                if 'incongruent' in cond:
                    results["cond_has_incongruent"] = True
                elif 'congruent' in cond:
                    results["cond_has_congruent"] = True
                
                # Logic check: Stimulus direction vs corrAns
                # Assumption: center character determines direction
                if len(stim) >= 1:
                    center_char = stim[len(stim)//2]
                    expected = ""
                    if center_char in ['<', 'L', 'l']:
                        expected = "left"
                    elif center_char in ['>', 'R', 'r']:
                        expected = "right"
                    
                    if expected and expected not in corr:
                        results["cond_logic_valid"] = False
                        if len(results["cond_logic_errors"]) < 3:
                            results["cond_logic_errors"].append(f"Row {i+1}: Stim '{stim}' center '{center_char}' expects '{expected}', got '{corr}'")
            
    except Exception as e:
        print(f"CSV Parse Error: {e}")

# --- Analyze Experiment XML ---
if os.path.isfile(EXP_FILE):
    results["exp_file_exists"] = True
    mtime = int(os.path.getmtime(EXP_FILE))
    if mtime > results["task_start_time"]:
        results["exp_file_modified"] = True
        
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["exp_is_valid_xml"] = True
        
        # Check Routines
        routines = root.find("Routines")
        if routines is not None:
            for routine in routines:
                name = routine.get("name", "").lower()
                
                # Loose matching for routine names
                if "instruct" in name:
                    results["exp_has_instructions"] = True
                if "trial" in name:
                    results["exp_has_trial"] = True
                    
                    # Check components inside trial routine
                    for comp in routine:
                        comp_type = comp.tag
                        
                        # Text component variable check
                        if "Text" in comp_type:
                            for param in comp:
                                if param.get("name") == "text" and "$" in param.get("val", ""):
                                    results["exp_text_uses_var"] = True
                        
                        # Keyboard component variable check
                        if "Key" in comp_type or "Keyboard" in comp_type:
                            for param in comp:
                                if param.get("name") == "correctAns" and "$" in param.get("val", ""):
                                    results["exp_kb_uses_var"] = True
                                if param.get("name") == "allowedKeys":
                                    results["exp_kb_allowed_keys"] = param.get("val", "")

        # Check Loops
        flow = root.find("Flow")
        if flow is not None:
            for item in flow:
                if "Loop" in item.tag:
                    results["exp_has_loop"] = True
                    for param in item:
                        if param.get("name") == "nReps":
                            try:
                                results["exp_loop_nreps"] = int(param.get("val", 0))
                            except:
                                pass
                        if param.get("name") == "conditionsFile":
                            results["exp_loop_file_ref"] = param.get("val", "")

    except Exception as e:
        print(f"XML Parse Error: {e}")

# Save results
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_flanker_task_result.json
echo "=== Export complete ==="