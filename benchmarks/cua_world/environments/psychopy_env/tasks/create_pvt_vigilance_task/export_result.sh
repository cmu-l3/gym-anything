#!/bin/bash
echo "=== Exporting create_pvt_vigilance_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# We will export file metadata and content analysis to a JSON file
# Using python for robust XML/CSV parsing inside the container
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/pvt_task.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions/pvt_trials.csv"
RESULT_FILE = "/tmp/pvt_result.json"

results = {
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    
    # File Existence & Integrity
    "exp_exists": False,
    "exp_modified": False,
    "cond_exists": False,
    "cond_modified": False,
    
    # Conditions File Analysis
    "cond_rows": 0,
    "cond_values": [],
    "cond_headers": [],
    
    # Experiment Structure Analysis
    "is_valid_xml": False,
    "has_isi_wait": False,
    "has_reaction_test": False,
    "has_feedback": False,
    "has_loop": False,
    
    # Specific PVT Features
    "counter_updates_every_frame": False,
    "counter_is_red": False,
    "counter_uses_time_var": False,
    "feedback_logic_found": False,
    "false_start_logic_found": False,
    "variable_isi_found": False
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
    if int(os.path.getmtime(COND_FILE)) > results["task_start_time"]:
        results["cond_modified"] = True
    
    try:
        with open(COND_FILE, 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
            if rows:
                results["cond_headers"] = rows[0]
                results["cond_rows"] = len(rows) - 1
                # Try to extract numbers from the first column or any column that looks like ISI
                # We look for the sequence 2.0, 5.0, 3.5, 8.0, 4.0 regardless of column order
                all_values = []
                for row in rows[1:]:
                    for cell in row:
                        try:
                            all_values.append(float(cell))
                        except ValueError:
                            pass
                results["cond_values"] = all_values
    except Exception as e:
        print(f"CSV Parse Error: {e}")

# 2. Analyze Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    if int(os.path.getmtime(EXP_FILE)) > results["task_start_time"]:
        results["exp_modified"] = True
        
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["is_valid_xml"] = True
        
        # Check Routines
        routines = root.findall(".//Routine")
        for r in routines:
            name = r.get("name", "").lower()
            if "wait" in name or "isi" in name:
                results["has_isi_wait"] = True
            if "reaction" in name or "test" in name or "pvt" in name:
                results["has_reaction_test"] = True
            if "feedback" in name:
                results["has_feedback"] = True
                
        # Check specific components
        # Find the Text component that acts as the counter
        text_comps = root.findall(".//TextComponent")
        for tc in text_comps:
            text_val = ""
            color_val = ""
            updates_val = ""
            
            for param in tc:
                if param.get("name") == "text":
                    text_val = param.get("val", "")
                    updates_val = param.get("updates", "")
                if param.get("name") == "color":
                    color_val = param.get("val", "")
            
            # Check for millisecond counter logic (t*1000)
            if "t*1000" in text_val or "t * 1000" in text_val:
                results["counter_uses_time_var"] = True
                if updates_val == "set every frame":
                    results["counter_updates_every_frame"] = True
                if "red" in color_val.lower():
                    results["counter_is_red"] = True

        # Check for Code component or Feedback logic
        # Looking for code that checks reaction time (< 0.15 or < 150)
        code_comps = root.findall(".//CodeComponent")
        full_code = ""
        for cc in code_comps:
            for param in cc:
                if param.get("name") in ["Begin Routine", "Each Frame", "End Routine"]:
                    full_code += param.get("val", "") + "\n"
        
        # Also check text components that might use logic in the text field itself
        # e.g. $msg
        
        if "0.15" in full_code or "150" in full_code:
            results["false_start_logic_found"] = True
        if "FALSE START" in full_code or "False Start" in full_code:
            results["feedback_logic_found"] = True
            
        # Check Loop for variable ISI
        # We need to find where the loop is defined and if the wait routine uses a variable
        # Simplified check: Look for a static wait component with a variable duration
        static_comps = root.findall(".//StaticComponent") # Wait is Static in XML sometimes? No, usually Keyboard or Code
        # Actually wait is usually implicit or a text component with duration. 
        # Let's check ALL components for a duration that looks like a variable
        all_params = root.findall(".//Param")
        for p in all_params:
            if p.get("name") == "stopVal": # Duration
                val = p.get("val", "")
                if "$" in val and "isi" in val.lower(): # e.g. $isi_duration
                    results["variable_isi_found"] = True

    except Exception as e:
        print(f"XML Parse Error: {e}")

# Save results
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
PYEOF

cat /tmp/pvt_result.json
echo "=== Export complete ==="