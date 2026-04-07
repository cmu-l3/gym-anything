#!/bin/bash
echo "=== Exporting Simon Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# We use an embedded Python script to robustly parse the XML and CSV
# instead of relying on fragile bash grep/sed chains.
python3 << 'PYEOF'
import json
import os
import csv
import sys
import datetime
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/simon_task/simon_task.psyexp"
CSV_FILE = "/home/ga/PsychoPyExperiments/simon_task/simon_conditions.csv"
RESULT_FILE = "/tmp/task_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "files": {
        "exp_exists": False,
        "csv_exists": False,
        "exp_modified": False,
        "csv_modified": False
    },
    "csv_analysis": {
        "valid": False,
        "columns": [],
        "row_count": 0,
        "has_required_cols": False,
        "is_balanced": False,
        "consistent_mapping": False,
        "rows_data": [] # Simplified for validation
    },
    "exp_analysis": {
        "valid_xml": False,
        "has_trial_routine": False,
        "has_feedback_routine": False,
        "has_loop": False,
        "conditions_file_ref": "",
        "stimulus": {
            "found": False,
            "updates_pos": False,
            "updates_color": False,
            "uses_pos_var": False,
            "uses_color_var": False
        },
        "response": {
            "found": False,
            "uses_corrAns_var": False,
            "stores_correct": False
        }
    }
}

# 1. File Existence & Modification Check
try:
    with open("/home/ga/.task_start_time") as f:
        start_time = int(f.read().strip())
except:
    start_time = 0

if os.path.exists(EXP_FILE):
    results["files"]["exp_exists"] = True
    if os.path.getmtime(EXP_FILE) > start_time:
        results["files"]["exp_modified"] = True

if os.path.exists(CSV_FILE):
    results["files"]["csv_exists"] = True
    if os.path.getmtime(CSV_FILE) > start_time:
        results["files"]["csv_modified"] = True

# 2. CSV Analysis
if results["files"]["csv_exists"]:
    try:
        with open(CSV_FILE, 'r') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                # Normalize headers to lowercase
                headers = [h.strip().lower() for h in reader.fieldnames]
                results["csv_analysis"]["columns"] = headers
                
                rows = list(reader)
                results["csv_analysis"]["row_count"] = len(rows)
                
                # Check required columns (flexible matching)
                req_cols = ["color", "pos", "corrans"] 
                # Map actual headers to required concepts
                col_map = {}
                for h in headers:
                    if "color" in h: col_map["color"] = h
                    if "pos" in h: col_map["pos"] = h
                    if "corr" in h or "ans" in h: col_map["corrans"] = h
                
                if len(col_map) >= 3:
                    results["csv_analysis"]["has_required_cols"] = True
                    results["csv_analysis"]["valid"] = True
                    
                    # Check Logic
                    # 1. Balance: Count combinations
                    counts = {}
                    color_response_map = {}
                    
                    valid_logic = True
                    for row in rows:
                        # Extract raw values using the map
                        c = row.get(col_map.get("color", ""), "").strip().lower()
                        p = row.get(col_map.get("pos", ""), "").strip().lower()
                        a = row.get(col_map.get("corrans", ""), "").strip().lower()
                        
                        # Store simplified data for verifier
                        results["csv_analysis"]["rows_data"].append({"c": c, "p": p, "a": a})
                        
                        # Check Mapping Consistency (Red should always be Left, etc.)
                        if c not in color_response_map:
                            color_response_map[c] = a
                        elif color_response_map[c] != a:
                            results["csv_analysis"]["consistent_mapping"] = False
                    
                    if len(color_response_map) > 0:
                        results["csv_analysis"]["consistent_mapping"] = True

                    # Check Balance (Congruent vs Incongruent)
                    # This is hard to check perfectly without knowing their specific string values
                    # So we just check if we have roughly equal row counts for unique conditions
                    unique_rows = set([(r[col_map["color"]], r[col_map["pos"]]) for r in rows])
                    if len(unique_rows) >= 4:
                        results["csv_analysis"]["is_balanced"] = True

    except Exception as e:
        print(f"CSV Error: {e}")

# 3. Experiment XML Analysis
if results["files"]["exp_exists"]:
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["exp_analysis"]["valid_xml"] = True
        
        # Check Routines
        routines = root.findall(".//Routine")
        for r in routines:
            name = r.get("name", "").lower()
            if "trial" in name:
                results["exp_analysis"]["has_trial_routine"] = True
                
                # Check Components in Trial
                for comp in r:
                    # Polygon/ShapeStim
                    if comp.tag == "PolygonComponent" or "Polygon" in str(comp.tag):
                        results["exp_analysis"]["stimulus"]["found"] = True
                        for param in comp:
                            pname = param.get("name")
                            pval = param.get("val")
                            pupdates = param.get("updates")
                            
                            if pname == "pos":
                                if "$" in str(pval) or "pos" in str(pval):
                                    results["exp_analysis"]["stimulus"]["uses_pos_var"] = True
                                if pupdates == "set every repeat":
                                    results["exp_analysis"]["stimulus"]["updates_pos"] = True
                            
                            if pname in ["fillColor", "color"]:
                                if "$" in str(pval) or "color" in str(pval):
                                    results["exp_analysis"]["stimulus"]["uses_color_var"] = True
                                if pupdates == "set every repeat":
                                    results["exp_analysis"]["stimulus"]["updates_color"] = True
                    
                    # Keyboard
                    if comp.tag == "KeyboardComponent" or "Keyboard" in str(comp.tag):
                        results["exp_analysis"]["response"]["found"] = True
                        for param in comp:
                            pname = param.get("name")
                            pval = param.get("val")
                            
                            if pname == "correctAns":
                                if "$" in str(pval) or "Ans" in str(pval):
                                    results["exp_analysis"]["response"]["uses_corrAns_var"] = True
                            if pname == "storeCorrect" and pval == "True":
                                results["exp_analysis"]["response"]["stores_correct"] = True

            if "feedback" in name:
                results["exp_analysis"]["has_feedback_routine"] = True

        # Check Loops
        loops = root.findall(".//LoopInitiator")
        if loops:
            results["exp_analysis"]["has_loop"] = True
            for l in loops:
                for param in l:
                    if param.get("name") == "conditionsFile":
                        results["exp_analysis"]["conditions_file_ref"] = param.get("val")

    except Exception as e:
        print(f"XML Error: {e}")

# Save results
with open(RESULT_FILE, 'w') as f:
    json.dump(results, f, indent=2)

PYEOF

# Clean permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="