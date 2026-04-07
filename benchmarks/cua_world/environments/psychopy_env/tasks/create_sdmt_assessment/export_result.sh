#!/bin/bash
echo "=== Exporting create_sdmt_assessment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import subprocess
import re
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/sdmt_task.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions/sdmt_conditions.csv"
RESULT_FILE = "/tmp/sdmt_result.json"

results = {
    "exp_exists": False,
    "cond_exists": False,
    "exp_valid_xml": False,
    "cond_valid_csv": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    # CSV Data
    "csv_row_count": 0,
    "csv_mappings_correct": False,
    "csv_symbols_found": [],
    # Experiment Structure
    "has_instructions": False,
    "has_trial": False,
    "has_loop": False,
    "loop_type": "",
    "loop_nreps": 0,
    # Components
    "has_static_key": False,
    "has_dynamic_probe": False,
    "has_keyboard": False,
    "has_code_component": False,
    # Code Logic
    "code_uses_clock": False,
    "code_checks_90s": False,
    "code_terminates_loop": False,
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

# 1. Analyze Conditions File
if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    try:
        with open(COND_FILE, 'r', newline='') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            results["csv_row_count"] = len(rows)
            
            # Normalize headers
            headers = [h.strip().lower() for h in reader.fieldnames or []]
            if 'symbol' in headers and ('corrans' in headers or 'correctans' in headers or 'answer' in headers):
                results["cond_valid_csv"] = True
                
                # Check mappings
                required_map = {
                    '@': '1', '#': '2', '$': '3', '%': '4', '&': '5', 
                    '*': '6', '(': '7', ')': '8', '!': '9'
                }
                found_map = {}
                for row in rows:
                    # Find the symbol column
                    sym = None
                    ans = None
                    for k, v in row.items():
                        if k.strip().lower() == 'symbol':
                            sym = v.strip()
                        elif k.strip().lower() in ['corrans', 'correctans', 'answer']:
                            ans = v.strip()
                    if sym and ans:
                        found_map[sym] = ans
                        results["csv_symbols_found"].append(sym)
                
                # Verify exact mappings
                correct_count = 0
                for r_sym, r_ans in required_map.items():
                    if found_map.get(r_sym) == r_ans:
                        correct_count += 1
                
                if correct_count == 9:
                    results["csv_mappings_correct"] = True
    except Exception as e:
        print(f"CSV Error: {e}")

# 2. Analyze Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["exp_valid_xml"] = True
        
        # Check Routines
        routines = root.findall(".//Routine")
        for r in routines:
            r_name = r.get("name", "").lower()
            if "instruct" in r_name:
                results["has_instructions"] = True
            if "trial" in r_name:
                results["has_trial"] = True
                
                # Check components inside trial
                for comp in r:
                    c_type = comp.tag
                    c_name = comp.get("name", "")
                    
                    # Text Components
                    if "Text" in c_type:
                        text_val = ""
                        for param in comp:
                            if param.get("name") == "text":
                                text_val = param.get("val", "")
                        
                        # Check for variable (Dynamic Probe)
                        if "$" in text_val and "symbol" in text_val.lower():
                            results["has_dynamic_probe"] = True
                        
                        # Check for Static Key (contains multiple numbers/symbols)
                        if any(x in text_val for x in ["@=1", "1=@", "@ = 1", "Key", "key"]):
                            results["has_static_key"] = True

                    # Keyboard
                    if "Key" in c_type or "Keyboard" in c_type:
                        results["has_keyboard"] = True
                    
                    # Code Component
                    if "Code" in c_type:
                        results["has_code_component"] = True
                        code_content = ""
                        # Gather code from all timing tabs
                        for param in comp:
                            p_name = param.get("name")
                            if p_name in ["Begin Routine", "Each Frame", "End Routine", "Begin Experiment"]:
                                code_content += param.get("val", "") + "\n"
                        
                        # Analyze Logic
                        if "clock" in code_content.lower() or "gettime" in code_content.lower() or "t" in code_content.split(): # 't' is standard psychopy time var
                            results["code_uses_clock"] = True
                        
                        if "90" in code_content:
                            results["code_checks_90s"] = True
                        
                        if ".finished" in code_content and "= true" in code_content.lower():
                            results["code_terminates_loop"] = True
                        if "break" in code_content: # Alternative termination
                             results["code_terminates_loop"] = True

        # Check Loops
        loops = root.findall(".//LoopInitiator")
        if loops:
            results["has_loop"] = True
            for loop in loops:
                # Check parameters
                for param in loop:
                    if param.get("name") == "loopType" and param.get("val") == "random":
                        results["loop_type"] = "random"
                    if param.get("name") == "nReps":
                        try:
                            val = float(param.get("val", "0"))
                            results["loop_nreps"] = val
                        except:
                            results["loop_nreps"] = 0 # variable or invalid

    except Exception as e:
        print(f"XML Error: {e}")

# Save JSON
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
os.chmod(RESULT_FILE, 0o666)
PYEOF

cat /tmp/sdmt_result.json
echo "=== Export complete ==="