#!/bin/bash
echo "=== Exporting create_pitch_discrimination result ==="

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

EXP_FILE = "/home/ga/PsychoPyExperiments/pitch_discrimination.psyexp"
CSV_FILE = "/home/ga/PsychoPyExperiments/conditions/pitch_conditions.csv"
RESULT_FILE = "/tmp/create_pitch_discrimination_result.json"

results = {
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    "exp_file_exists": False,
    "csv_file_exists": False,
    "exp_file_modified": False,
    "csv_file_modified": False,
    # CSV Analysis
    "csv_row_count": 0,
    "csv_headers": [],
    "csv_logic_score": 0, # Percentage of correctly logical rows
    "csv_has_deviants": False,
    "csv_has_base": False,
    # Experiment Analysis
    "sound_component_count": 0,
    "keyboard_component_count": 0,
    "sound_uses_variables": False,
    "sound_durations": [],
    "sound_start_times": [],
    "gap_duration_check": False,
    "has_loop": False,
    "loop_links_csv": False
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

# Check CSV
if os.path.isfile(CSV_FILE):
    results["csv_file_exists"] = True
    if os.path.getmtime(CSV_FILE) > results["task_start_time"]:
        results["csv_file_modified"] = True
    
    try:
        with open(CSV_FILE, 'r') as f:
            reader = csv.DictReader(f)
            results["csv_headers"] = reader.fieldnames
            rows = list(reader)
            results["csv_row_count"] = len(rows)
            
            correct_logic_count = 0
            deviants_found = set()
            base_found = False
            
            # Identify columns dynamically
            freq_cols = [h for h in reader.fieldnames if 'freq' in h.lower() or 'hz' in h.lower()]
            ans_col = next((h for h in reader.fieldnames if 'corr' in h.lower() or 'ans' in h.lower()), None)
            
            if len(freq_cols) >= 2 and ans_col:
                col1, col2 = freq_cols[0], freq_cols[1]
                for row in rows:
                    try:
                        f1 = float(row[col1])
                        f2 = float(row[col2])
                        ans = str(row[ans_col]).strip()
                        
                        # Check frequencies
                        if f1 == 440: base_found = True
                        if f2 == 440: base_found = True
                        if f1 != 440: deviants_found.add(f1)
                        if f2 != 440: deviants_found.add(f2)
                        
                        # Check logic
                        expected = '1' if f1 > f2 else '2'
                        if ans == expected:
                            correct_logic_count += 1
                    except ValueError:
                        pass
                
                if len(rows) > 0:
                    results["csv_logic_score"] = (correct_logic_count / len(rows)) * 100
            
            results["csv_has_base"] = base_found
            results["csv_has_deviants"] = len(deviants_found) >= 3 # At least 3 different deviants used
            
    except Exception as e:
        print(f"CSV Error: {e}")

# Check Experiment
if os.path.isfile(EXP_FILE):
    results["exp_file_exists"] = True
    if os.path.getmtime(EXP_FILE) > results["task_start_time"]:
        results["exp_file_modified"] = True
        
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        
        # Analyze Components in Routines
        routines = root.findall(".//Routine")
        for routine in routines:
            # Sound Components
            sounds = routine.findall(".//SoundComponent") 
            # Note: In newer PsychoPy, components are generic with 'type="Sound"' attribute, 
            # or strictly typed tags. We'll search generic Component nodes and check attributes.
            
            for comp in routine:
                comp_type = comp.get('type', comp.tag)
                
                if 'Sound' in comp_type:
                    results["sound_component_count"] += 1
                    # Check params
                    for param in comp:
                        name = param.get('name')
                        val = param.get('val')
                        
                        if name == 'sound':
                            if '$' in str(val):
                                results["sound_uses_variables"] = True
                        
                        if name == 'stopVal':
                            try:
                                results["sound_durations"].append(float(val))
                            except:
                                pass # Variable duration
                        
                        if name == 'startVal':
                            try:
                                results["sound_start_times"].append(float(val))
                            except:
                                pass

                if 'Key' in comp_type:
                    results["keyboard_component_count"] += 1

        # Check Gap Logic
        # Sort start times to find gap
        starts = sorted(results["sound_start_times"])
        if len(starts) >= 2:
            # Assuming first sound starts at 0 or close to it
            # Gap = Start2 - (Start1 + Duration1)
            # Duration is usually 0.4
            # Ideal: Start1=0, Start2=1.0 (0.4 play + 0.6 gap)
            if starts[1] >= 0.9: # Allow some tolerance
                results["gap_duration_check"] = True

        # Check Loop
        loops = root.findall(".//LoopInitiator")
        if len(loops) > 0:
            results["has_loop"] = True
            for loop in loops:
                # Check for conditions file link
                for param in loop.iter():
                    if param.get('name') == 'conditionsFile':
                        if 'pitch_conditions.csv' in str(param.get('val')):
                            results["loop_links_csv"] = True

    except Exception as e:
        print(f"PsyExp Error: {e}")

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_pitch_discrimination_result.json
echo "=== Export complete ==="