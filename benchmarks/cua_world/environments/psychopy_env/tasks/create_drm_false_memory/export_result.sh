#!/bin/bash
echo "=== Exporting DRM False Memory Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_end.png

# Use Python to analyze the experiment file and CSVs
# This runs inside the container to package everything into a JSON result
python3 << 'PYEOF'
import json
import os
import csv
import sys
import datetime
import xml.etree.ElementTree as ET

# Configuration
EXP_FILE = "/home/ga/PsychoPyExperiments/drm_false_memory.psyexp"
STUDY_CSV = "/home/ga/PsychoPyExperiments/conditions/drm_study_words.csv"
TEST_CSV = "/home/ga/PsychoPyExperiments/conditions/drm_test_words.csv"
RESULT_FILE = "/tmp/drm_task_result.json"
TASK_START_FILE = "/home/ga/.task_start_time"
NONCE_FILE = "/home/ga/.task_nonce"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    "files": {
        "exp": {"exists": False, "modified": False, "size": 0},
        "study": {"exists": False, "modified": False, "size": 0},
        "test": {"exists": False, "modified": False, "size": 0}
    },
    "exp_structure": {
        "valid_xml": False,
        "routines": [],
        "loops": [],
        "components": []
    },
    "study_data": {
        "valid_csv": False,
        "columns": [],
        "row_count": 0,
        "words": []
    },
    "test_data": {
        "valid_csv": False,
        "columns": [],
        "row_count": 0,
        "rows": [] # Storing fuller data for logic checks
    }
}

# 1. Load Task Metadata
try:
    with open(TASK_START_FILE) as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

try:
    with open(NONCE_FILE) as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# 2. Check Files existence and modification
for key, path in [("exp", EXP_FILE), ("study", STUDY_CSV), ("test", TEST_CSV)]:
    if os.path.exists(path):
        results["files"][key]["exists"] = True
        results["files"][key]["size"] = os.path.getsize(path)
        mtime = int(os.path.getmtime(path))
        if mtime > results["task_start_time"]:
            results["files"][key]["modified"] = True

# 3. Analyze Experiment XML
if results["files"]["exp"]["exists"]:
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["exp_structure"]["valid_xml"] = True
        
        # Extract Routines
        for routine in root.findall(".//Routine"):
            r_name = routine.get("name", "unknown")
            results["exp_structure"]["routines"].append(r_name)
            
            # Extract Components in Routine
            for comp in routine:
                c_type = comp.tag
                c_name = comp.get("name", "unknown")
                results["exp_structure"]["components"].append({
                    "name": c_name,
                    "type": c_type,
                    "routine": r_name
                })
        
        # Extract Loops
        for loop in root.findall(".//LoopInitiator"):
            loop_props = {}
            for param in loop:
                if param.get("name") == "name":
                    loop_props["name"] = param.get("val")
                if param.get("name") == "conditionsFile":
                    loop_props["file"] = param.get("val")
            results["exp_structure"]["loops"].append(loop_props)
            
    except Exception as e:
        print(f"XML Parse Error: {e}")

# 4. Analyze Study CSV
if results["files"]["study"]["exists"]:
    try:
        with open(STUDY_CSV, 'r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                results["study_data"]["valid_csv"] = True
                results["study_data"]["columns"] = [c.strip() for c in reader.fieldnames]
                for row in reader:
                    # Normalize keys/values
                    clean_row = {k.strip().lower(): v.strip() for k, v in row.items() if k}
                    results["study_data"]["words"].append(clean_row.get("word", "").lower())
                results["study_data"]["row_count"] = len(results["study_data"]["words"])
    except Exception as e:
        print(f"Study CSV Error: {e}")

# 5. Analyze Test CSV
if results["files"]["test"]["exists"]:
    try:
        with open(TEST_CSV, 'r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                results["test_data"]["valid_csv"] = True
                results["test_data"]["columns"] = [c.strip() for c in reader.fieldnames]
                for row in reader:
                    clean_row = {k.strip().lower(): v.strip().lower() for k, v in row.items() if k}
                    results["test_data"]["rows"].append(clean_row)
                results["test_data"]["row_count"] = len(results["test_data"]["rows"])
    except Exception as e:
        print(f"Test CSV Error: {e}")

# Save Result
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
PYEOF

cat /tmp/drm_task_result.json
echo "=== Export complete ==="