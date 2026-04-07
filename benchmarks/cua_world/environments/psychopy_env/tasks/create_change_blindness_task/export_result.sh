#!/bin/bash
echo "=== Exporting Change Blindness Task Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python script to analyze all artifacts
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import xml.etree.ElementTree as ET
import csv

EXP_FILE = "/home/ga/PsychoPyExperiments/change_blindness.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions.csv"
STIM_DIR = "/home/ga/PsychoPyExperiments/stimuli"
RESULT_FILE = "/tmp/change_blindness_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    
    # Files
    "exp_exists": False,
    "exp_modified": False,
    "cond_exists": False,
    "stim_dir_exists": False,
    "image_a_exists": False,
    "image_b_exists": False,
    "image_a_size": 0,
    
    # Structure
    "is_valid_xml": False,
    "has_nested_loops": False,
    "loops": [],
    "routines": [],
    "components": [],
    "code_components": [],
    
    # Content
    "cond_columns": [],
    "timing_pattern_found": False, # Checks for 0.24 and 0.08 durations
    "loop_termination_logic": False
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

# Check Stimuli
if os.path.isdir(STIM_DIR):
    results["stim_dir_exists"] = True
    img_a = os.path.join(STIM_DIR, "airplane_a.jpg")
    img_b = os.path.join(STIM_DIR, "airplane_b.jpg")
    
    if os.path.isfile(img_a):
        results["image_a_exists"] = True
        results["image_a_size"] = os.path.getsize(img_a)
    if os.path.isfile(img_b):
        results["image_b_exists"] = True

# Check Conditions File
if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    try:
        with open(COND_FILE, 'r') as f:
            reader = csv.reader(f)
            header = next(reader, [])
            results["cond_columns"] = [h.strip() for h in header]
    except:
        pass

# Check Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    mtime = int(os.path.getmtime(EXP_FILE))
    if mtime > results["task_start_time"]:
        results["exp_modified"] = True
        
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["is_valid_xml"] = True
        
        # Analyze Flow/Loops
        flow = root.find("Flow")
        loop_stack = []
        if flow is not None:
            for elem in flow:
                if "LoopInitiator" in elem.tag:
                    loop_name = elem.get("name")
                    loop_stack.append(loop_name)
                    results["loops"].append(loop_name)
                    # Simple heuristic for nesting: if stack > 1, we have nesting
                    if len(loop_stack) > 1:
                        results["has_nested_loops"] = True
                elif "LoopTerminator" in elem.tag:
                    if loop_stack:
                        loop_stack.pop()
        
        # Analyze Routines and Components
        routines = root.find("Routines")
        durations = []
        
        if routines is not None:
            for routine in routines:
                rname = routine.get("name")
                results["routines"].append(rname)
                
                for comp in routine:
                    cname = comp.get("name")
                    ctype = comp.tag
                    results["components"].append({"name": cname, "type": ctype})
                    
                    # Check durations for timing pattern
                    for param in comp:
                        if param.get("name") == "durationEstim": # or stop val
                            try:
                                val = float(param.get("val"))
                                durations.append(val)
                            except:
                                pass
                        # Check code components for termination logic
                        if "Code" in ctype and param.get("name") == "Each Frame":
                            code_val = param.get("val", "")
                            if "finished" in code_val and "True" in code_val:
                                results["loop_termination_logic"] = True
                                
        # Check timing pattern (fuzzy match)
        # We expect 0.24 and 0.08 to appear
        has_stim_dur = any(abs(d - 0.24) < 0.01 for d in durations)
        has_isi_dur = any(abs(d - 0.08) < 0.01 for d in durations)
        if has_stim_dur and has_isi_dur:
            results["timing_pattern_found"] = True

    except Exception as e:
        print(f"XML Parse Error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
PYEOF

cat /tmp/change_blindness_result.json
echo "=== Export complete ==="