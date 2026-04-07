#!/bin/bash
echo "=== Exporting create_paired_associate_learning result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis to ensure consistency
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import subprocess
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/paired_associates/paired_associates.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/paired_associates/conditions.csv"
RESULT_FILE = "/tmp/task_result.json"

results = {
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    "exp_file_exists": False,
    "exp_file_modified": False,
    "csv_file_exists": False,
    "csv_valid": False,
    "csv_pairs_count": 0,
    "csv_headers": [],
    "components": {
        "textbox": False,
        "code": False,
        "text": False,
        "keyboard": False
    },
    "code_content": {
        "has_lower": False,
        "has_strip": False,
        "has_if_else": False,
        "sets_msg": False,
        "sets_color": False
    },
    "has_loop": False,
    "conditions_file_linked": False,
    "xml_valid": False
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

# 1. Analyze Conditions CSV
if os.path.isfile(COND_FILE):
    results["csv_file_exists"] = True
    try:
        with open(COND_FILE, 'r', newline='') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                results["csv_headers"] = [h.strip().lower() for h in reader.fieldnames]
                rows = list(reader)
                results["csv_pairs_count"] = len(rows)
                
                # Check for required columns
                if "cue" in results["csv_headers"] and "target" in results["csv_headers"]:
                    results["csv_valid"] = True
                    
                # Check for correct data (sample check)
                target_pairs = {"bees": "hive", "lion": "roar", "soup": "bowl"}
                correct_data_count = 0
                for row in rows:
                    c = row.get("cue", "").strip().lower()
                    t = row.get("target", "").strip().lower()
                    if c in target_pairs and target_pairs[c] == t:
                        correct_data_count += 1
                results["correct_data_match_count"] = correct_data_count

    except Exception as e:
        results["csv_error"] = str(e)

# 2. Analyze Experiment XML
if os.path.isfile(EXP_FILE):
    results["exp_file_exists"] = True
    mtime = int(os.path.getmtime(EXP_FILE))
    if mtime > results["task_start_time"]:
        results["exp_file_modified"] = True

    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["xml_valid"] = True

        # Check components
        for comp in root.findall(".//Component"):
            comp_type = comp.get("val", "") # Older versions
            if not comp_type:
                # Newer versions might use tag name or other attributes, but often it's nested
                # Iterate params to find type
                pass
            
            # Better way: iterate over routines and their children
        
        # Re-scan via Routines to get component types reliably
        routines = root.findall(".//Routine")
        for routine in routines:
            for child in routine:
                comp_type = child.tag
                # Check specific params to confirm component type if tag is generic
                # Usually tag is specific e.g. <TextBoxComponent> or <TextComponent>
                
                if "TextBox" in comp_type:
                    results["components"]["textbox"] = True
                elif "Code" in comp_type:
                    results["components"]["code"] = True
                    # Analyze code content
                    for param in child:
                        if param.get("name") in ["Begin Routine", "End Routine", "Each Frame"]:
                            code_text = param.get("val", "").lower()
                            if ".lower()" in code_text or ".upper()" in code_text:
                                results["code_content"]["has_lower"] = True
                            if ".strip()" in code_text:
                                results["code_content"]["has_strip"] = True
                            if "if " in code_text and "else" in code_text:
                                results["code_content"]["has_if_else"] = True
                            if "msg" in code_text or "message" in code_text or "feedback" in code_text:
                                results["code_content"]["sets_msg"] = True
                            if "color" in code_text:
                                results["code_content"]["sets_color"] = True
                                
                elif "Text" in comp_type and "TextBox" not in comp_type:
                    results["components"]["text"] = True
                elif "Keyboard" in comp_type:
                    results["components"]["keyboard"] = True

        # Check Loops
        loops = root.findall(".//LoopInitiator")
        if loops:
            results["has_loop"] = True
            for loop in loops:
                for param in loop:
                    if param.get("name") == "conditionsFile":
                        val = param.get("val", "")
                        if "conditions.csv" in val:
                            results["conditions_file_linked"] = True

    except Exception as e:
        results["xml_error"] = str(e)

# Write result
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="