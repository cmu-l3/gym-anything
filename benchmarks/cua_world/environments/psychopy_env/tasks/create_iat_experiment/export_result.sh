#!/bin/bash
echo "=== Exporting Create IAT Experiment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import xml.etree.ElementTree as ET

BASE_DIR = "/home/ga/PsychoPyExperiments/IAT"
EXP_FILE = os.path.join(BASE_DIR, "iat_experiment.psyexp")
COND_DIR = os.path.join(BASE_DIR, "conditions")
RESULT_FILE = "/tmp/create_iat_experiment_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    "dir_exists": False,
    "cond_dir_exists": False,
    "exp_file_exists": False,
    "exp_valid_xml": False,
    "routines_count": 0,
    "loops_count": 0,
    "loops_referencing_csvs": 0,
    "has_category_labels": False,
    "csv_status": {},
    "file_timestamps_valid": True
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

# Check directories
if os.path.isdir(BASE_DIR):
    results["dir_exists"] = True
if os.path.isdir(COND_DIR):
    results["cond_dir_exists"] = True

# Validate Stimuli Lists
STIMULI = {
    "flower": ["rose", "tulip", "daisy", "lily"],
    "insect": ["ant", "spider", "beetle", "mosquito"],
    "pleasant": ["joy", "love", "peace", "happy"],
    "unpleasant": ["agony", "terrible", "horrible", "nasty"]
}

def validate_csv(filename, expected_rows, mapping_check_func):
    filepath = os.path.join(COND_DIR, filename)
    status = {
        "exists": False,
        "valid_structure": False,
        "row_count": 0,
        "correct_stimuli": False,
        "correct_mappings": False,
        "error": ""
    }
    
    if not os.path.isfile(filepath):
        return status
    
    status["exists"] = True
    
    # Check modification time
    if int(os.path.getmtime(filepath)) < results["task_start_time"]:
        results["file_timestamps_valid"] = False

    try:
        with open(filepath, 'r', newline='') as f:
            reader = csv.DictReader(f)
            headers = [h.lower() for h in (reader.fieldnames or [])]
            
            if not all(col in headers for col in ['stimulus', 'category', 'corrans']):
                status["error"] = "Missing required columns"
                return status
            
            rows = list(reader)
            status["row_count"] = len(rows)
            
            if len(rows) < expected_rows:
                status["error"] = f"Expected {expected_rows} rows, found {len(rows)}"
                return status
                
            status["valid_structure"] = True
            
            # Check content
            stimuli_correct = True
            mappings_correct = True
            
            for row in rows:
                stim = row.get('stimulus', '').strip().lower()
                cat = row.get('category', '').strip().lower()
                ans = row.get('corrAns', '').strip().lower()
                
                # Check mapping via callback
                if not mapping_check_func(stim, cat, ans):
                    mappings_correct = False
                
                # Check if stimulus belongs to expected sets
                found_stim = False
                for s_list in STIMULI.values():
                    if stim in s_list:
                        found_stim = True
                        break
                if not found_stim:
                    stimuli_correct = False
            
            status["correct_stimuli"] = stimuli_correct
            status["correct_mappings"] = mappings_correct
            
    except Exception as e:
        status["error"] = str(e)
        
    return status

# Define mapping checks
def check_b1(stim, cat, ans):
    # Flower -> Left (e), Insect -> Right (i)
    if stim in STIMULI["flower"] and ans == 'e': return True
    if stim in STIMULI["insect"] and ans == 'i': return True
    return False

def check_b2(stim, cat, ans):
    # Pleasant -> Left (e), Unpleasant -> Right (i)
    if stim in STIMULI["pleasant"] and ans == 'e': return True
    if stim in STIMULI["unpleasant"] and ans == 'i': return True
    return False

def check_b3(stim, cat, ans):
    # Combined: Flower/Pleasant -> e, Insect/Unpleasant -> i
    if (stim in STIMULI["flower"] or stim in STIMULI["pleasant"]) and ans == 'e': return True
    if (stim in STIMULI["insect"] or stim in STIMULI["unpleasant"]) and ans == 'i': return True
    return False

def check_b4(stim, cat, ans):
    # REVERSED: Insect -> Left (e), Flower -> Right (i)
    if stim in STIMULI["insect"] and ans == 'e': return True
    if stim in STIMULI["flower"] and ans == 'i': return True
    return False

def check_b5(stim, cat, ans):
    # Combined Incongruent: Insect/Pleasant -> e, Flower/Unpleasant -> i
    if (stim in STIMULI["insect"] or stim in STIMULI["pleasant"]) and ans == 'e': return True
    if (stim in STIMULI["flower"] or stim in STIMULI["unpleasant"]) and ans == 'i': return True
    return False

# Validate all CSVs
results["csv_status"]["block1"] = validate_csv("block1_target_practice.csv", 8, check_b1)
results["csv_status"]["block2"] = validate_csv("block2_attribute_practice.csv", 8, check_b2)
results["csv_status"]["block3"] = validate_csv("block3_combined_congruent.csv", 16, check_b3)
results["csv_status"]["block4"] = validate_csv("block4_reversed_target.csv", 8, check_b4)
results["csv_status"]["block5"] = validate_csv("block5_combined_incongruent.csv", 16, check_b5)

# Validate Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_file_exists"] = True
    
    # Check timestamp
    if int(os.path.getmtime(EXP_FILE)) < results["task_start_time"]:
        results["file_timestamps_valid"] = False

    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["exp_valid_xml"] = True
            
        routines = root.findall(".//Routine")
        results["routines_count"] = len(routines)
        
        loops = root.findall(".//LoopInitiator")
        results["loops_count"] = len(loops)
        
        # Check if loops reference our CSVs
        csv_names = [
            "block1_target_practice.csv", "block2_attribute_practice.csv",
            "block3_combined_congruent.csv", "block4_reversed_target.csv",
            "block5_combined_incongruent.csv"
        ]
        
        refs = 0
        for loop in loops:
            cond_param = loop.find(".//Param[@name='conditionsFile']")
            if cond_param is not None:
                val = cond_param.get('val', '')
                if any(name in val for name in csv_names):
                    refs += 1
        results["loops_referencing_csvs"] = refs
        
        # Check for category labels (multiple text components in a routine)
        # A standard trial has 1 text for stimulus. IAT needs labels, so >1 text component per routine.
        max_text_comps = 0
        for routine in routines:
            text_comps = 0
            for child in routine:
                if "TextComponent" in child.tag:
                    text_comps += 1
            if text_comps > max_text_comps:
                max_text_comps = text_comps
        
        if max_text_comps >= 3: # Stimulus + Left Label + Right Label
            results["has_category_labels"] = True
            
    except Exception as e:
        print(f"XML Error: {e}")

# Save results
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
PYEOF

cat /tmp/create_iat_experiment_result.json
echo "=== Export complete ==="