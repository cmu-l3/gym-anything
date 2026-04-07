#!/bin/bash
echo "=== Exporting digit span task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
TASK_DIR="/home/ga/PsychoPyExperiments/digit_span"
CSV_FILE="$TASK_DIR/digit_span_conditions.csv"
PSYEXP_FILE="$TASK_DIR/digit_span.psyexp"

# Use Python to analyze both files and produce a single JSON result
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import xml.etree.ElementTree as ET

TASK_DIR = "/home/ga/PsychoPyExperiments/digit_span"
CSV_FILE = os.path.join(TASK_DIR, "digit_span_conditions.csv")
PSYEXP_FILE = os.path.join(TASK_DIR, "digit_span.psyexp")
RESULT_FILE = "/tmp/digit_span_result.json"

results = {
    "csv_exists": False,
    "csv_valid": False,
    "csv_stats": {},
    "psyexp_exists": False,
    "psyexp_valid_xml": False,
    "psyexp_structure": {},
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": ""
}

# Read task start time and nonce
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except: pass

try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except: pass

# --- Analyze CSV ---
if os.path.exists(CSV_FILE):
    results["csv_exists"] = True
    # Check timestamp
    mtime = int(os.path.getmtime(CSV_FILE))
    results["csv_modified_during_task"] = mtime > results["task_start_time"]
    
    try:
        with open(CSV_FILE, 'r', newline='') as f:
            reader = csv.DictReader(f)
            headers = [h.strip() for h in (reader.fieldnames or [])]
            rows = list(reader)
            
            results["csv_stats"] = {
                "headers": headers,
                "row_count": len(rows),
                "has_required_cols": all(col in headers for col in ["span_length", "digits", "direction", "correct_response"]),
                "forward_trials": 0,
                "backward_trials": 0,
                "valid_digit_format": True
            }
            
            for row in rows:
                direction = row.get("direction", "").lower()
                if "forward" in direction:
                    results["csv_stats"]["forward_trials"] += 1
                elif "backward" in direction:
                    results["csv_stats"]["backward_trials"] += 1
                
                # Check digit format (e.g., "5-8-2")
                digits = row.get("digits", "")
                if not all(part.isdigit() for part in digits.split("-")):
                    results["csv_stats"]["valid_digit_format"] = False

            results["csv_valid"] = True
    except Exception as e:
        results["csv_error"] = str(e)

# --- Analyze PsyExp ---
if os.path.exists(PSYEXP_FILE):
    results["psyexp_exists"] = True
    mtime = int(os.path.getmtime(PSYEXP_FILE))
    results["psyexp_modified_during_task"] = mtime > results["task_start_time"]

    try:
        tree = ET.parse(PSYEXP_FILE)
        root = tree.getroot()
        results["psyexp_valid_xml"] = True
        
        structure = {
            "routines": [],
            "loops": [],
            "has_code_component": False,
            "has_text_component": False,
            "has_keyboard_component": False,
            "has_conditions_ref": False
        }
        
        # Check routines
        for routine in root.iter("Routine"):
            rname = routine.get("name")
            structure["routines"].append(rname)
            
            for comp in routine:
                ctype = comp.tag
                if "Code" in ctype:
                    structure["has_code_component"] = True
                    # Check code content for digit logic
                    for param in comp.findall("Param"):
                        if param.get("name") in ["Begin Routine", "Each Frame"]:
                            if "split" in param.get("val", "") or "digit" in param.get("val", ""):
                                structure["code_logic_detected"] = True
                if "Text" in ctype:
                    structure["has_text_component"] = True
                if "Key" in ctype or "Keyboard" in ctype or "TextBox" in ctype:
                    structure["has_keyboard_component"] = True
        
        # Check loops
        for loop in root.iter("LoopInitiator"):
            loop_data = {}
            for param in loop.findall(".//Param"):
                if param.get("name") == "conditionsFile":
                    val = param.get("val", "")
                    loop_data["conditionsFile"] = val
                    if "digit_span_conditions.csv" in val:
                        structure["has_conditions_ref"] = True
                if param.get("name") == "loopType":
                    loop_data["loopType"] = param.get("val", "")
            structure["loops"].append(loop_data)
            
        results["psyexp_structure"] = structure
        
    except Exception as e:
        results["psyexp_error"] = str(e)

# Write result
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/digit_span_result.json
echo "=== Export complete ==="