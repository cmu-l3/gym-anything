#!/bin/bash
echo "=== Exporting create_auditory_p300_with_triggers result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python script to parse both XML (experiment) and CSV (conditions)
python3 << 'PYEOF'
import json
import os
import sys
import csv
import xml.etree.ElementTree as ET
import datetime

EXP_FILE = "/home/ga/PsychoPyExperiments/p300_oddball.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions/oddball_conditions.csv"
RESULT_FILE = "/tmp/p300_result.json"

results = {
    "exp_exists": False,
    "cond_exists": False,
    "task_start_time": 0,
    "timestamp": datetime.datetime.now().isoformat(),
    # Conditions File Metrics
    "csv_valid": False,
    "total_trials": 0,
    "standard_count": 0,
    "target_count": 0,
    "standard_ratio": 0.0,
    "has_trigger_col": False,
    "trigger_values": [],
    # Experiment Structure Metrics
    "xml_valid": False,
    "has_sound": False,
    "has_parallel_port": False,
    "port_address": "",
    "sound_start": None,
    "port_start": None,
    "port_duration": None,
    "port_data_variable": False, # Is data set to a variable like $trigger?
    "sync_correct": False,       # port_start == sound_start
    "loop_references_csv": False
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

# --- Analyze Conditions CSV ---
if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    try:
        with open(COND_FILE, 'r', newline='') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            if reader.fieldnames:
                results["csv_valid"] = True
                results["total_trials"] = len(rows)
                
                # Identify trigger column (allow variations)
                trigger_col = None
                for col in reader.fieldnames:
                    if "trig" in col.lower() or "code" in col.lower():
                        trigger_col = col
                        results["has_trigger_col"] = True
                        break
                
                # Count conditions
                for row in rows:
                    # Check for standard/target keywords in any column
                    row_str = str(row).lower()
                    if "standard" in row_str:
                        results["standard_count"] += 1
                    elif "target" in row_str or "oddball" in row_str:
                        results["target_count"] += 1
                    
                    if trigger_col and row[trigger_col]:
                        try:
                            results["trigger_values"].append(int(row[trigger_col]))
                        except:
                            pass

                if results["total_trials"] > 0:
                    results["standard_ratio"] = results["standard_count"] / results["total_trials"]

    except Exception as e:
        print(f"CSV Parse Error: {e}")

# --- Analyze Experiment XML ---
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["xml_valid"] = True
        
        # Check Loops for CSV reference
        for loop in root.findall(".//LoopInitiator"):
            cond_param = loop.find(".//Param[@name='conditionsFile']")
            if cond_param is not None and "oddball_conditions.csv" in cond_param.get('val', ''):
                results["loop_references_csv"] = True

        # Check Routines for Components
        # We need to find the trial routine specifically
        routines = root.findall(".//Routine")
        for routine in routines:
            # Look for components in this routine
            sound_comp = None
            port_comp = None
            
            for comp in routine:
                comp_type = comp.tag
                
                # Check Sound
                if "Sound" in comp_type:
                    sound_comp = comp
                    results["has_sound"] = True
                    # Get start time
                    for param in comp:
                        if param.get("name") == "startVal":
                            try:
                                results["sound_start"] = float(param.get("val"))
                            except:
                                results["sound_start"] = param.get("val") # Keep as string if var

                # Check Parallel Port
                if "ParallelPort" in comp_type:
                    port_comp = comp
                    results["has_parallel_port"] = True
                    for param in comp:
                        name = param.get("name")
                        val = param.get("val")
                        if name == "startVal":
                            try:
                                results["port_start"] = float(val)
                            except:
                                results["port_start"] = val
                        elif name == "address":
                            results["port_address"] = val
                        elif name == "stopVal":
                            results["port_duration"] = val
                        elif name == "startData":
                            if "$" in val:
                                results["port_data_variable"] = True

            # Check synchronization within this routine
            if sound_comp is not None and port_comp is not None:
                # If both exist in the same routine, check timing
                if results["sound_start"] is not None and results["port_start"] is not None:
                    # Compare floats with tolerance, or strings directly
                    try:
                        t1 = float(results["sound_start"])
                        t2 = float(results["port_start"])
                        if abs(t1 - t2) < 0.001:
                            results["sync_correct"] = True
                    except:
                        if results["sound_start"] == results["port_start"]:
                            results["sync_correct"] = True

    except Exception as e:
        print(f"XML Parse Error: {e}")

# Save result
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
PYEOF

cat /tmp/p300_result.json
echo "=== Export complete ==="