#!/bin/bash
echo "=== Exporting create_recognition_confidence_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import subprocess
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/recognition_confidence.psyexp"
STUDY_CSV = "/home/ga/PsychoPyExperiments/conditions/study_list.csv"
TEST_CSV = "/home/ga/PsychoPyExperiments/conditions/test_list.csv"
RESULT_FILE = "/tmp/recognition_confidence_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    "psychopy_running": False,
    # File Existence
    "exp_file_exists": False,
    "study_csv_exists": False,
    "test_csv_exists": False,
    "files_modified_during_task": False,
    # CSV Content
    "study_words_found": [],
    "test_words_count": 0,
    "test_csv_headers": [],
    "has_correct_ans_col": False,
    "test_mapping_correct": False, # Checks if old=y, new=n
    # Experiment Structure
    "is_valid_xml": False,
    "routines": [],
    "loops": [],
    "has_slider": False,
    "has_code_component": False,
    "code_logic_found": False, # The specific conditional logic
    "logic_snippet": ""
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

# PsychoPy running
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

# Check CSVs
if os.path.isfile(STUDY_CSV):
    results["study_csv_exists"] = True
    try:
        with open(STUDY_CSV, 'r', newline='') as f:
            reader = csv.DictReader(f)
            # Normalize headers
            if reader.fieldnames:
                clean_headers = [h.strip().lower() for h in reader.fieldnames]
                if "word" in clean_headers:
                    for row in reader:
                        # Find the value for 'word' column case-insensitively
                        for k, v in row.items():
                            if k.strip().lower() == 'word':
                                results["study_words_found"].append(v.strip())
    except:
        pass

if os.path.isfile(TEST_CSV):
    results["test_csv_exists"] = True
    try:
        with open(TEST_CSV, 'r', newline='') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                results["test_csv_headers"] = [h.strip() for h in reader.fieldnames]
                clean_headers = [h.lower() for h in results["test_csv_headers"]]
                if "corrans" in clean_headers or "correctans" in clean_headers:
                    results["has_correct_ans_col"] = True
                
                rows = list(reader)
                results["test_words_count"] = len(rows)
                
                # Check mapping
                correct_map_count = 0
                for row in rows:
                    # messy normalization to find keys
                    row_lower = {k.strip().lower(): v.strip().lower() for k, v in row.items()}
                    rtype = row_lower.get('type', '')
                    rcorr = row_lower.get('corrans', row_lower.get('correctans', ''))
                    
                    if (rtype == 'old' and 'y' in rcorr) or (rtype == 'new' and 'n' in rcorr):
                        correct_map_count += 1
                
                if len(rows) > 0 and correct_map_count == len(rows):
                    results["test_mapping_correct"] = True
    except:
        pass

# Check Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_file_exists"] = True
    mtime = int(os.path.getmtime(EXP_FILE))
    if mtime > results["task_start_time"]:
        results["files_modified_during_task"] = True

    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True
        
        # Analyze Routines
        routines = root.find("Routines") or root.find(".//Routines")
        if routines is not None:
            for routine in routines:
                rname = routine.get("name")
                results["routines"].append(rname)
                
                # Check components inside routines
                for comp in routine:
                    comp_type = comp.tag
                    
                    if "Slider" in comp_type:
                        results["has_slider"] = True
                    
                    if "Code" in comp_type:
                        results["has_code_component"] = True
                        # Look for logic in code
                        for param in comp:
                            if param.get("name") in ["Begin Routine", "beginRoutine"]:
                                val = param.get("val", "")
                                if "continueRoutine" in val and "False" in val:
                                    # Basic check for conditional structure
                                    if "if" in val and ("key" in val or "resp" in val):
                                        results["code_logic_found"] = True
                                        results["logic_snippet"] = val[:100] # Save snippet for debug

        # Analyze Loops
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            for elem in flow:
                if "Loop" in elem.tag:
                    # Get loop parameters
                    loop_props = {}
                    for param in elem:
                        loop_props[param.get("name")] = param.get("val")
                    results["loops"].append(loop_props)

    except Exception as e:
        print(f"XML Parse Error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/recognition_confidence_result.json
echo "=== Export complete ==="