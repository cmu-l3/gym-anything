#!/bin/bash
echo "=== Exporting create_fitts_law_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Use Python for robust XML parsing and CSV math validation
python3 << 'PYEOF'
import json
import os
import sys
import csv
import math
import xml.etree.ElementTree as ET
import datetime

PSYEXP_PATH = "/home/ga/PsychoPyExperiments/fitts_law/fitts_task.psyexp"
CSV_PATH = "/home/ga/PsychoPyExperiments/fitts_law/conditions/fitts_targets.csv"
RESULT_FILE = "/tmp/task_result.json"

results = {
    "files_exist": False,
    "csv_valid": False,
    "csv_math_score": 0.0,  # Percentage of rows correct
    "csv_structure_valid": False,
    "experiment_valid": False,
    "units_correct": False,
    "routines_found": [],
    "components_valid": {
        "home_stim": False,
        "home_mouse": False,
        "reach_stim": False,
        "reach_mouse": False,
        "loop_linked": False
    },
    "variable_usage": {
        "pos_x": False,
        "target_w": False
    },
    "timestamp": datetime.datetime.now().isoformat()
}

# 1. Check Files Existence
if os.path.exists(PSYEXP_PATH) and os.path.exists(CSV_PATH):
    results["files_exist"] = True

# 2. Validate CSV (Math and Structure)
if os.path.exists(CSV_PATH):
    try:
        with open(CSV_PATH, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
            # Check headers
            required_cols = {'target_w', 'target_amp', 'direction', 'pos_x'}
            headers = set(reader.fieldnames) if reader.fieldnames else set()
            
            # Allow loose matching on headers (case insensitive/strip)
            clean_headers = {h.strip().lower() for h in headers}
            clean_required = {h.lower() for h in required_cols}
            
            if clean_required.issubset(clean_headers):
                results["csv_structure_valid"] = True
            
            # Check Math: pos_x = (amp / 2) * direction
            correct_rows = 0
            total_rows = 0
            
            # Expected values logic
            for row in rows:
                try:
                    # Normalize keys
                    row_lower = {k.strip().lower(): v for k, v in row.items()}
                    
                    amp = float(row_lower.get('target_amp', 0))
                    direction = float(row_lower.get('direction', 0))
                    pos_x = float(row_lower.get('pos_x', 0))
                    
                    expected_pos = (amp / 2.0) * direction
                    
                    # Check with tolerance
                    if abs(pos_x - expected_pos) < 0.001:
                        correct_rows += 1
                    total_rows += 1
                except ValueError:
                    continue # Skip malformed rows
            
            if total_rows > 0:
                results["csv_math_score"] = (correct_rows / total_rows) * 100
                results["total_rows"] = total_rows
            
    except Exception as e:
        results["csv_error"] = str(e)

# 3. Validate PsychoPy Experiment (XML Parsing)
if os.path.exists(PSYEXP_PATH):
    try:
        tree = ET.parse(PSYEXP_PATH)
        root = tree.getroot()
        results["experiment_valid"] = True

        # Check Units
        settings = root.find("Settings")
        if settings is not None:
            for param in settings.findall("Param"):
                if param.get("name") == "units" and param.get("val") == "height":
                    results["units_correct"] = True

        # Check Routines
        routines = root.findall(".//Routine")
        results["routines_found"] = [r.get("name") for r in routines]
        
        # Check Home Routine
        home_routine = None
        for r in routines:
            if "home" in r.get("name", "").lower():
                home_routine = r
                break
        
        if home_routine is not None:
            # Check for Mouse ending routine on click
            for comp in home_routine:
                if "Mouse" in comp.tag:
                    force_end = False
                    valid_click = False
                    for param in comp:
                        if param.get("name") == "forceEndRoutineOnPress" and param.get("val") == "any click":
                            force_end = True # "any click" or "valid click" depending on version/config
                        if param.get("name") == "forceEndRoutineOnPress" and param.get("val") == "valid click":
                            force_end = True
                        if param.get("name") == "clickable":
                            # Should reference the home button
                            if len(param.get("val", "")) > 0:
                                valid_click = True
                    if force_end and valid_click:
                        results["components_valid"]["home_mouse"] = True

        # Check Reach Routine
        reach_routine = None
        for r in routines:
            if "reach" in r.get("name", "").lower():
                reach_routine = r
                break
        
        if reach_routine is not None:
            for comp in reach_routine:
                # Check Stimulus Variables
                if "Polygon" in comp.tag or "Image" in comp.tag:
                    for param in comp:
                        name = param.get("name")
                        val = param.get("val")
                        if name == "size" and ("target_w" in val or "target_w" in val):
                            results["variable_usage"]["target_w"] = True
                        if name == "pos" and ("pos_x" in val):
                            results["variable_usage"]["pos_x"] = True
                            results["components_valid"]["reach_stim"] = True

                # Check Mouse
                if "Mouse" in comp.tag:
                    force_end = False
                    valid_click = False
                    save_params = False
                    for param in comp:
                        if param.get("name") == "forceEndRoutineOnPress" and param.get("val") == "valid click":
                            force_end = True
                        if param.get("name") == "clickable" and len(param.get("val", "")) > 0:
                            valid_click = True
                        if param.get("name") == "saveParamsClickable" and "name" in param.get("val"):
                             # Check if it saves time/name
                             pass 
                    if force_end and valid_click:
                        results["components_valid"]["reach_mouse"] = True

        # Check Loop
        flow = root.find("Flow")
        if flow is not None:
            for child in flow:
                if "Loop" in child.tag:
                    for param in child:
                        if param.get("name") == "conditionsFile" and "fitts" in param.get("val").lower():
                            results["components_valid"]["loop_linked"] = True

    except Exception as e:
        results["experiment_error"] = str(e)

# Write result
with open(RESULT_FILE, 'w') as f:
    json.dump(results, f, indent=2)

print(f"Analysis complete. Results saved to {RESULT_FILE}")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="