#!/bin/bash
echo "=== Exporting create_delay_discounting_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call to analyze both CSV and XML structure
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import xml.etree.ElementTree as ET

CSV_FILE = "/home/ga/PsychoPyExperiments/conditions/kirby_mcq.csv"
EXP_FILE = "/home/ga/PsychoPyExperiments/delay_discounting.psyexp"
RESULT_FILE = "/tmp/create_delay_discounting_task_result.json"

results = {
    "task_start_time": 0,
    "timestamp": datetime.datetime.now().isoformat(),
    "result_nonce": "",
    
    # CSV Metrics
    "csv_exists": False,
    "csv_modified": False,
    "csv_rows": 0,
    "csv_cols": [],
    "csv_data": [],  # Store data for verifier to check against ground truth
    "csv_headers_valid": False,
    
    # Experiment Metrics
    "exp_exists": False,
    "exp_modified": False,
    "exp_valid_xml": False,
    "has_loop": False,
    "loop_file_ref": "",
    "has_trial_routine": False,
    "text_components_count": 0,
    "has_sir_var": False,
    "has_ldr_var": False,
    "has_days_var": False,
    "keyboard_keys": ""
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

# --- Analyze CSV ---
if os.path.isfile(CSV_FILE):
    results["csv_exists"] = True
    if int(os.path.getmtime(CSV_FILE)) > results["task_start_time"]:
        results["csv_modified"] = True
    
    try:
        with open(CSV_FILE, 'r', newline='') as f:
            reader = csv.DictReader(f)
            results["csv_cols"] = [c.strip().lower() for c in (reader.fieldnames or [])]
            
            # Check for required columns
            req = {"sir", "ldr", "days"}
            if req.issubset(set(results["csv_cols"])):
                results["csv_headers_valid"] = True
                
            data = []
            for row in reader:
                # Sanitize keys
                clean_row = {k.strip().lower(): v.strip() for k, v in row.items() if k}
                data.append(clean_row)
            
            results["csv_rows"] = len(data)
            results["csv_data"] = data
    except Exception as e:
        print(f"CSV Error: {e}")

# --- Analyze Experiment ---
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    if int(os.path.getmtime(EXP_FILE)) > results["task_start_time"]:
        results["exp_modified"] = True
        
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["exp_valid_xml"] = True
            
        # Check Loops
        for loop in root.iter("LoopInitiator"):
            results["has_loop"] = True
            # Check conditions file param
            for param in loop.iter("Param"):
                if param.get("name") == "conditionsFile":
                    results["loop_file_ref"] = param.get("val", "")
                    
        # Check Components in Routines
        for routine in root.iter("Routine"):
            # Check text components
            for comp in routine:
                ctype = comp.tag
                if "Text" in ctype:
                    results["text_components_count"] += 1
                    # Check for variable usage in text field
                    for param in comp.iter("Param"):
                        if param.get("name") == "text":
                            val = param.get("val", "")
                            if "$sir" in val: results["has_sir_var"] = True
                            if "$ldr" in val: results["has_ldr_var"] = True
                            if "$days" in val: results["has_days_var"] = True
                            
                if "Key" in ctype:
                    for param in comp.iter("Param"):
                        if param.get("name") == "allowedKeys":
                            results["keyboard_keys"] = param.get("val", "")

    except Exception as e:
        print(f"XML Error: {e}")

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_delay_discounting_task_result.json
echo "=== Export complete ==="