#!/bin/bash
echo "=== Exporting create_staircase_threshold result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Use Python to parse the .psyexp XML file and extract detailed structure
# This avoids fragile grep/sed parsing for complex XML structures
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess
import xml.etree.ElementTree as ET

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/contrast_threshold_staircase.psyexp"
RESULT_FILE = "/tmp/create_staircase_threshold_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "file_size": 0,
    "is_valid_xml": False,
    "psychopy_running": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    # Task specific checks
    "has_staircase_loop": False,
    "loop_params": {},
    "has_instructions_routine": False,
    "has_trial_routine": False,
    "has_grating": False,
    "grating_contrast_variable": False,
    "has_keyboard": False,
    "flow_order_correct": False, # Instructions before loop
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

if os.path.isfile(OUTPUT_FILE):
    results["file_exists"] = True
    results["file_size"] = os.path.getsize(OUTPUT_FILE)

    # Check modification time against task start
    mtime = int(os.path.getmtime(OUTPUT_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    try:
        tree = ET.parse(OUTPUT_FILE)
        root = tree.getroot()
        
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True

        # Check Routines
        routines = root.find("Routines")
        if routines is not None:
            for routine in routines:
                name = routine.get("name", "").lower()
                
                if "instruction" in name:
                    results["has_instructions_routine"] = True
                
                if "trial" in name:
                    results["has_trial_routine"] = True
                    # Check components inside trial
                    for comp in routine:
                        comp_type = comp.tag
                        if "Grating" in comp_type:
                            results["has_grating"] = True
                            # Check contrast param
                            for param in comp:
                                if param.get("name") == "contrast":
                                    val = param.get("val", "")
                                    update = param.get("updates", "")
                                    # Check if it uses a variable (contains $ or is a variable name)
                                    # And updates every repeat
                                    if ("$" in val or val.isidentifier()) and update == "set every repeat":
                                        results["grating_contrast_variable"] = True
                        
                        if "Keyboard" in comp_type:
                            results["has_keyboard"] = True

        # Check Flow and Loops
        flow = root.find("Flow")
        if flow is not None:
            loop_found = False
            first_element = True
            
            for elem in flow:
                # Check order: instructions should be before the loop
                if first_element:
                    routine_name = elem.get("name", "").lower()
                    if "instruction" in routine_name:
                        results["flow_order_correct"] = True
                    first_element = False

                if "LoopInitiator" in elem.tag:
                    loop_type = elem.get("loopType", "").lower()
                    # Check for staircase specifically
                    if loop_type == "staircase" or loop_type == "interleavedstaircase":
                        results["has_staircase_loop"] = True
                        loop_found = True
                        
                        # Extract params
                        for param in elem:
                            pname = param.get("name")
                            pval = param.get("val")
                            if pname:
                                results["loop_params"][pname] = pval

    except Exception as e:
        print(f"Error parsing XML: {e}", file=sys.stderr)

# Save results
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_staircase_threshold_result.json
echo "=== Export complete ==="