#!/bin/bash
echo "=== Exporting create_visual_search_task result ==="

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
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/visual_search/visual_search.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/visual_search/search_conditions.csv"
RESULT_FILE = "/tmp/create_visual_search_task_result.json"

results = {
    "exp_exists": False,
    "cond_exists": False,
    "exp_valid_xml": False,
    "cond_valid_csv": False,
    "files_modified": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    
    # CSV Metrics
    "csv_columns": [],
    "csv_row_count": 0,
    "has_target_col": False,
    "has_setsize_col": False,
    
    # Experiment Metrics
    "component_count": 0,
    "text_component_count": 0,
    "has_code_component": False,
    "code_content": "",
    "has_random_import": False,
    "has_shuffle": False,
    "has_pos_assignment": False,
    "has_opacity_logic": False,
    "has_orientation_logic": False
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

# Check CSV
if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    try:
        if os.path.getmtime(COND_FILE) > results["task_start_time"]:
            results["files_modified"] = True
            
        with open(COND_FILE, 'r') as f:
            reader = csv.DictReader(f)
            results["csv_columns"] = reader.fieldnames if reader.fieldnames else []
            rows = list(reader)
            results["csv_row_count"] = len(rows)
            
        lower_cols = [c.lower() for c in results["csv_columns"]]
        if any("target" in c for c in lower_cols):
            results["has_target_col"] = True
        if any("set" in c and "size" in c for c in lower_cols):
            results["has_setsize_col"] = True
            
        results["cond_valid_csv"] = True
    except Exception as e:
        print(f"CSV Error: {e}")

# Check Experiment
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    try:
        if os.path.getmtime(EXP_FILE) > results["task_start_time"]:
            results["files_modified"] = True
            
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["exp_valid_xml"] = True
            
        # Analyze Components
        components = root.findall(".//Component") # PsychoPy XML structure varies, searching broadly
        if not components:
            # Fallback for newer XML structure where components are children of Routine
            routines = root.findall(".//Routine")
            components = []
            for r in routines:
                components.extend(list(r))
        
        results["component_count"] = len(components)
        
        for comp in components:
            ctype = comp.get("componentType", comp.tag) # Handle different XML versions
            
            if "Text" in ctype:
                results["text_component_count"] += 1
                
            if "Code" in ctype:
                results["has_code_component"] = True
                # Extract code content
                for param in comp:
                    name = param.get("name")
                    val = param.get("val")
                    if name in ["Begin Routine", "Begin Experiment", "Each Frame"] and val:
                        results["code_content"] += "\n" + val

        # Analyze Code Content
        code = results["code_content"].lower()
        if "random" in code or "shuffle" in code or "choice" in code:
            results["has_random_import"] = True
        if "shuffle" in code or "permutation" in code:
            results["has_shuffle"] = True
        if ".pos" in code or "setpos" in code or "pos=" in code:
            results["has_pos_assignment"] = True
        if "opacity" in code or "autodraw" in code or "visual" in code: # "visual" often used in logic
            results["has_opacity_logic"] = True
        if "ori" in code or "orientation" in code:
            results["has_orientation_logic"] = True

    except Exception as e:
        print(f"XML Error: {e}")

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_visual_search_task_result.json
echo "=== Export complete ==="