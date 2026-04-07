#!/bin/bash
echo "=== Exporting create_ultimatum_game result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Use Python to analyze files and generate a comprehensive JSON result
# This avoids race conditions and permission issues with multiple shell commands
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import csv
import subprocess
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/ultimatum_game.psyexp"
CSV_FILE = "/home/ga/PsychoPyExperiments/ug_conditions.csv"
RESULT_FILE = "/tmp/create_ultimatum_game_result.json"
TASK_START_FILE = "/home/ga/.task_start_time"
NONCE_FILE = "/home/ga/.task_nonce"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    "exp_exists": False,
    "exp_modified": False,
    "csv_exists": False,
    "csv_modified": False,
    "csv_valid": False,
    "csv_columns": [],
    "csv_rows": [],
    "xml_valid": False,
    "has_loop": False,
    "linked_csv": "",
    "has_code_component": False,
    "code_content": "",
    "has_text_stim": False,
    "text_stim_content": "",
    "has_feedback_routine": False
}

# 1. Read Task Metadata (Start time, Nonce)
try:
    if os.path.exists(TASK_START_FILE):
        with open(TASK_START_FILE) as f:
            results["task_start_time"] = int(f.read().strip())
    if os.path.exists(NONCE_FILE):
        with open(NONCE_FILE) as f:
            results["result_nonce"] = f.read().strip()
except Exception as e:
    print(f"Error reading metadata: {e}")

# 2. Analyze CSV File
if os.path.isfile(CSV_FILE):
    results["csv_exists"] = True
    if os.path.getmtime(CSV_FILE) > results["task_start_time"]:
        results["csv_modified"] = True
    
    try:
        with open(CSV_FILE, 'r', newline='') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                results["csv_columns"] = [c.strip() for c in reader.fieldnames]
                # Read rows to verify data content
                for row in reader:
                    # Clean whitespace from keys and values
                    clean_row = {k.strip(): v.strip() for k, v in row.items() if k}
                    results["csv_rows"].append(clean_row)
        results["csv_valid"] = True
    except Exception as e:
        print(f"Error parsing CSV: {e}")

# 3. Analyze PsychoPy Experiment File (XML)
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    if os.path.getmtime(EXP_FILE) > results["task_start_time"]:
        results["exp_modified"] = True

    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["xml_valid"] = True

        # Check for Loop
        for loop in root.findall(".//LoopInitiator"):
            # Check if it links to the CSV
            for param in loop.findall(".//Param"):
                if param.get('name') == 'conditionsFile':
                    val = param.get('val')
                    results["linked_csv"] = val
                    results["has_loop"] = True

        # Check Routines and Components
        routines = root.findall(".//Routine")
        for routine in routines:
            # Check for Feedback routine
            if "feedback" in routine.get('name', '').lower():
                results["has_feedback_routine"] = True

            for comp in routine:
                # Check Code Component
                if comp.tag == "Code":
                    results["has_code_component"] = True
                    # Extract logic from 'End Routine' code
                    for param in comp.findall("Param"):
                        if param.get('name') == 'End Routine':
                            results["code_content"] += param.get('val', '') + "\n"
                
                # Check Text Component
                if comp.tag == "Text":
                    results["has_text_stim"] = True
                    for param in comp.findall("Param"):
                        if param.get('name') == 'text':
                            results["text_stim_content"] += param.get('val', '') + "|"

    except Exception as e:
        print(f"Error parsing XML: {e}")

# Save Result
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
PYEOF

cat /tmp/create_ultimatum_game_result.json
echo "=== Export complete ==="