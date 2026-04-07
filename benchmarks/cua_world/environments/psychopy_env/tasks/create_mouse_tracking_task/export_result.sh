#!/bin/bash
echo "=== Exporting create_mouse_tracking_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis to ensure consistency and performance
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import subprocess
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/mouse_tracking.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions/competitors.csv"
RESULT_FILE = "/tmp/mouse_tracking_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "result_nonce": "",
    "psychopy_running": False,
    
    # File Existence
    "exp_file_exists": False,
    "exp_file_modified": False,
    "cond_file_exists": False,
    "cond_file_modified": False,
    
    # Conditions File Analysis
    "cond_columns": [],
    "cond_row_count": 0,
    "has_required_columns": False,
    
    # Experiment Structure Analysis
    "is_valid_xml": False,
    "routines": [],
    "has_start_routine": False,
    "start_routine_has_mouse": False,
    "start_routine_has_button": False,
    "trial_routine_name": "",
    "trial_has_mouse": False,
    "mouse_save_state": "none",
    "mouse_save_every_frame": False,
    "structural_complexity": 0
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

# Check if PsychoPy is running
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

# Analyze Conditions File
if os.path.isfile(COND_FILE):
    results["cond_file_exists"] = True
    mtime = int(os.path.getmtime(COND_FILE))
    if mtime > results["task_start_time"]:
        results["cond_file_modified"] = True
    
    try:
        with open(COND_FILE, 'r', newline='') as f:
            reader = csv.reader(f)
            header = next(reader, [])
            rows = list(reader)
            
            results["cond_columns"] = [h.strip() for h in header]
            results["cond_row_count"] = len(rows)
            
            required = {"target_word", "distractor_word", "correct_side"}
            # minimal check: do we have at least 3 cols and do they look somewhat right?
            # strict check: do we have the exact names?
            # Let's check for intersection size
            found_req = sum(1 for h in results["cond_columns"] if h in required)
            results["has_required_columns"] = found_req >= 2  # Allow some flexibility
            
    except Exception as e:
        print(f"Error parsing CSV: {e}", file=sys.stderr)

# Analyze Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_file_exists"] = True
    mtime = int(os.path.getmtime(EXP_FILE))
    if mtime > results["task_start_time"]:
        results["exp_file_modified"] = True
        
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["is_valid_xml"] = True
        results["structural_complexity"] = len(root.findall(".//*[@name]"))
        
        routines = root.find("Routines")
        if routines is not None:
            # Identify Start Routine
            # Logic: A routine that is NOT the main trial loop (often named 'trial')
            # and contains a mouse and something at y=-0.7
            
            for routine in routines:
                r_name = routine.get("name")
                results["routines"].append(r_name)
                
                comps = list(routine)
                has_mouse = False
                has_low_stim = False
                
                for comp in comps:
                    c_type = comp.tag
                    
                    # Check for mouse
                    if "Mouse" in c_type:
                        has_mouse = True
                        
                        # Check configuration for continuous logging
                        # Param name="saveMouseState" val="every frame"
                        save_state = ""
                        for param in comp:
                            if param.get("name") == "saveMouseState":
                                save_state = param.get("val")
                        
                        # Check specifically for this routine if it's the trial routine
                        # We assume 'trial' is the main routine, or the one with words
                        # Heuristic: if it has 'target_word' text, it's the trial routine
                        is_trial = False
                        for c2 in comps:
                            for p2 in c2:
                                if p2.get("name") == "text" and "target" in str(p2.get("val")):
                                    is_trial = True
                        
                        if is_trial or r_name == "trial":
                            results["trial_routine_name"] = r_name
                            results["trial_has_mouse"] = True
                            results["mouse_save_state"] = str(save_state)
                            if "every frame" in str(save_state).lower() or "on every frame" in str(save_state).lower():
                                results["mouse_save_every_frame"] = True
                    
                    # Check for start button (stimulus at y ~ -0.7)
                    if "Text" in c_type or "Shape" in c_type or "Button" in c_type:
                        for param in comp:
                            if param.get("name") == "pos":
                                val = param.get("val")
                                # Loose check for -0.7 in the position string
                                if "-0.7" in str(val):
                                    has_low_stim = True

                # Determine if this is the start routine
                if has_mouse and has_low_stim:
                    results["has_start_routine"] = True
                    results["start_routine_has_mouse"] = True
                    results["start_routine_has_button"] = True

    except Exception as e:
        print(f"Error parsing XML: {e}", file=sys.stderr)

# Write results
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/mouse_tracking_result.json
echo "=== Export complete ==="