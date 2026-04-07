#!/bin/bash
echo "=== Exporting Face Inversion Task Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call to analyze both XML and CSV
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/face_inversion.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions/inversion_conditions.csv"
RESULT_FILE = "/tmp/face_inversion_result.json"

results = {
    "exp_exists": False,
    "cond_exists": False,
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    # XML Analysis
    "is_valid_xml": False,
    "has_image_component": False,
    "image_uses_var": False,
    "image_orientation_uses_var": False,
    "orientation_var_name": "",
    "has_keyboard": False,
    "keyboard_stores_correct": False,
    "keyboard_allowed_keys": "",
    "has_loop": False,
    "loop_file_ref": "",
    # CSV Analysis
    "csv_rows": 0,
    "csv_cols": [],
    "has_orientation_col": False,
    "has_category_col": False,
    "has_stimulus_col": False,
    "has_corrans_col": False,
    "has_upright": False,
    "has_inverted": False,
    "has_faces": False,
    "has_houses": False,
    "logic_correct": True, # Assume true, disprove if logic fails
    "logic_errors": []
}

# Read task start/nonce
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except: pass

try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except: pass

# Analyze Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["is_valid_xml"] = True
        
        # Check components
        for comp in root.findall(".//Component"):
            ctype = comp.get("val", "") # Older versions uses val, or look at tag/attributes? 
            # Actually Component is usually a wrapper, children have types.
            # In Builder XML, it's often <Routine><ImageComponent name="..."><Param name="image" val="$stimulus"/>...
            pass
            
        # Robust search for Image Component
        # Look for any element having an 'image' parameter
        image_params = root.findall(".//*[@name='image']")
        if image_params:
            results["has_image_component"] = True
            # Check if value starts with $
            val = image_params[0].get("val", "")
            if "$" in val:
                results["image_uses_var"] = True
                
            # Find parent component of this image param to check orientation
            # ElementTree doesn't support parent traversal easily, so we iterate routines
            
        routines = root.findall(".//Routine")
        for routine in routines:
            for child in routine:
                # Identify Image Component by check params
                params = {p.get("name"): p.get("val") for p in child.findall("Param")}
                
                if "image" in params:
                    results["has_image_component"] = True
                    if "$" in params.get("image", ""):
                        results["image_uses_var"] = True
                    
                    ori = params.get("ori", params.get("orientation", ""))
                    if "$" in ori:
                        results["image_orientation_uses_var"] = True
                        results["orientation_var_name"] = ori
                
                if "allowedKeys" in params:
                    results["has_keyboard"] = True
                    results["keyboard_allowed_keys"] = params.get("allowedKeys", "")
                    corr = params.get("correctAns", params.get("corrAns", ""))
                    if "$" in corr:
                        results["keyboard_stores_correct"] = True

        # Check Loop
        loops = root.findall(".//LoopInitiator")
        if loops:
            results["has_loop"] = True
            for loop in loops:
                # Check parameters inside loop
                params = {p.get("name"): p.get("val") for p in loop.findall(".//Param")}
                if "conditionsFile" in params:
                    results["loop_file_ref"] = params["conditionsFile"]

    except Exception as e:
        print(f"XML Error: {e}", file=sys.stderr)

# Analyze Conditions File
if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    try:
        with open(COND_FILE, 'r', newline='') as f:
            reader = csv.DictReader(f)
            results["csv_cols"] = [c.lower() for c in (reader.fieldnames or [])]
            rows = list(reader)
            results["csv_rows"] = len(rows)
            
            # Check column existence
            results["has_orientation_col"] = any(c in results["csv_cols"] for c in ["orientation", "ori"])
            results["has_category_col"] = any(c in results["csv_cols"] for c in ["category", "cat"])
            results["has_stimulus_col"] = any(c in results["csv_cols"] for c in ["stimulus", "image", "stimfile"])
            results["has_corrans_col"] = any(c in results["csv_cols"] for c in ["corrans", "correctans", "correct"])
            
            # Identify actual column names
            ori_col = next((c for c in reader.fieldnames if c.lower() in ["orientation", "ori"]), None)
            cat_col = next((c for c in reader.fieldnames if c.lower() in ["category", "cat"]), None)
            ans_col = next((c for c in reader.fieldnames if c.lower() in ["corrans", "correctans", "correct"]), None)
            
            if ori_col and cat_col and ans_col:
                for row in rows:
                    # Check orientations
                    ori_val = row[ori_col].strip()
                    if ori_val == "0": results["has_upright"] = True
                    if ori_val == "180": results["has_inverted"] = True
                    
                    # Check categories
                    cat_val = row[cat_col].strip().lower()
                    if "face" in cat_val: results["has_faces"] = True
                    if "house" in cat_val: results["has_houses"] = True
                    
                    # Check Logic
                    ans_val = row[ans_col].strip().lower().replace("'", "")
                    if "face" in cat_val and ans_val != "f":
                        results["logic_correct"] = False
                        results["logic_errors"].append(f"Face logic error: {row}")
                    if "house" in cat_val and ans_val != "h":
                        results["logic_correct"] = False
                        results["logic_errors"].append(f"House logic error: {row}")
            else:
                results["logic_correct"] = False
                results["logic_errors"].append("Missing required columns for logic check")

    except Exception as e:
        print(f"CSV Error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
PYEOF

cat /tmp/face_inversion_result.json
echo "=== Export complete ==="