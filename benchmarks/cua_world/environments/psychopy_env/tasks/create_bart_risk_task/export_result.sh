#!/bin/bash
echo "=== Exporting BART Task Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Analyze files using Python
python3 << 'PYEOF'
import json
import os
import sys
import csv
import xml.etree.ElementTree as ET
import datetime

EXP_FILE = "/home/ga/PsychoPyExperiments/bart_task.psyexp"
CSV_FILE = "/home/ga/PsychoPyExperiments/conditions/bart_config.csv"
RESULT_FILE = "/tmp/bart_task_result.json"

results = {
    "exp_exists": False,
    "csv_exists": False,
    "csv_valid": False,
    "csv_columns": [],
    "nested_loops": False,
    "dynamic_size": False,
    "logic_found": False,
    "feedback_found": False,
    "timestamp": datetime.datetime.now().isoformat(),
    "file_created_during_task": False
}

# 1. Check CSV
if os.path.exists(CSV_FILE):
    results["csv_exists"] = True
    try:
        with open(CSV_FILE, 'r') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                results["csv_columns"] = [c.strip() for c in reader.fieldnames]
                if "explosion_point" in results["csv_columns"]:
                    results["csv_valid"] = True
    except Exception as e:
        print(f"CSV Check Error: {e}")

# 2. Check Experiment File
if os.path.exists(EXP_FILE):
    results["exp_exists"] = True
    
    # Check timestamp
    try:
        with open("/home/ga/.task_start_time", "r") as f:
            start_time = int(f.read().strip())
        mtime = int(os.path.getmtime(EXP_FILE))
        if mtime > start_time:
            results["file_created_during_task"] = True
    except:
        pass

    # Parse XML
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        
        # Check for Nested Loops (at least 2 LoopInitiator elements)
        # Note: In .psyexp XML, LoopInitiator elements appear in the Flow section
        loops = root.findall(".//LoopInitiator")
        if len(loops) >= 2:
            results["nested_loops"] = True
            
        # Check components
        routines = root.findall(".//Routine")
        
        for routine in routines:
            # Check for Logic (Code Component)
            # We look for keywords like "pumps", "explosion", "pop", "bank" inside Code params
            for code in routine.findall(".//Code"):
                for param in code.findall("Param"):
                    val = param.get("val", "").lower()
                    if "pump" in val and ("if" in val or "+=" in val):
                        results["logic_found"] = True
            
            # Check for Visuals with Dynamic Size
            # Look for Polygon/Image with size updates
            for comp in routine:
                if comp.tag in ["Polygon", "Image"]:
                    for param in comp.findall("Param"):
                        if param.get("name") == "size":
                            val = param.get("val", "")
                            updates = param.get("updates", "")
                            # It's dynamic if updates is 'set every repeat' or 'set every frame'
                            # AND the value likely contains a variable (not just digits/comma)
                            if updates in ["set every repeat", "set every frame"]:
                                if any(c.isalpha() for c in val): # Has variable name
                                    results["dynamic_size"] = True

            # Check for Feedback routine naming or content
            rname = routine.get("name", "").lower()
            if "feedback" in rname:
                results["feedback_found"] = True

    except Exception as e:
        print(f"XML Parse Error: {e}")

with open(RESULT_FILE, 'w') as f:
    json.dump(results, f, indent=2)

print("Export complete.")
PYEOF

chmod 666 /tmp/bart_task_result.json 2>/dev/null || true
cat /tmp/bart_task_result.json
echo "=== Export complete ==="