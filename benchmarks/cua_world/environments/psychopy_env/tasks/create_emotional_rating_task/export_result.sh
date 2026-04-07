#!/bin/bash
echo "=== Exporting create_emotional_rating_task result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Define paths
EXP_FILE="/home/ga/PsychoPyExperiments/emotional_ratings.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/conditions/faces.csv"
RESULT_FILE="/tmp/task_result.json"

# 3. Analyze files using Python
python3 << PYEOF
import json
import os
import datetime
import csv
import xml.etree.ElementTree as ET

result = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    "exp_file_exists": False,
    "exp_file_modified": False,
    "cond_file_exists": False,
    "cond_file_modified": False,
    # XML Analysis
    "is_valid_xml": False,
    "component_counts": {},  # e.g. {"SliderComponent": 2, "ImageComponent": 1}
    "has_loop": False,
    "conditions_file_ref": "",
    "slider_labels": [],
    # CSV Analysis
    "csv_valid": False,
    "csv_rows": 0,
    "csv_columns": []
}

# Read start time/nonce
try:
    with open("/home/ga/.task_start_time") as f:
        result["task_start_time"] = int(f.read().strip())
except: pass

try:
    with open("/home/ga/.task_nonce") as f:
        result["result_nonce"] = f.read().strip()
except: pass

# Check Experiment File
if os.path.exists("$EXP_FILE"):
    result["exp_file_exists"] = True
    if os.path.getmtime("$EXP_FILE") > result["task_start_time"]:
        result["exp_file_modified"] = True
    
    try:
        tree = ET.parse("$EXP_FILE")
        root = tree.getroot()
        result["is_valid_xml"] = True
        
        # Count components
        comps = {}
        # Find all components (in routines)
        # Note: PsychoPy XML structure varies, components are usually children of Routine
        for routine in root.findall(".//Routine"):
            for child in routine:
                ctype = child.tag
                comps[ctype] = comps.get(ctype, 0) + 1
                
                # Check slider labels specifically
                if "Slider" in ctype:
                    # Look for labels param
                    for param in child:
                        if param.get("name") == "labels":
                            val = param.get("val")
                            if val:
                                result["slider_labels"].append(val)

        result["component_counts"] = comps
        
        # Check loop
        for loop in root.findall(".//LoopInitiator"):
            result["has_loop"] = True
            for param in loop:
                if param.get("name") == "conditionsFile":
                    result["conditions_file_ref"] = param.get("val", "")

    except Exception as e:
        print(f"XML Error: {e}")

# Check Conditions File
if os.path.exists("$COND_FILE"):
    result["cond_file_exists"] = True
    if os.path.getmtime("$COND_FILE") > result["task_start_time"]:
        result["cond_file_modified"] = True
        
    try:
        with open("$COND_FILE", 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
            if len(rows) > 0:
                result["csv_valid"] = True
                result["csv_columns"] = rows[0]
                result["csv_rows"] = len(rows) - 1 # exclude header
    except: pass

with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# 4. Set permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Result saved to $RESULT_FILE"
cat "$RESULT_FILE"