#!/bin/bash
echo "=== Exporting create_mental_rotation_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Use Python to parse the experiment file and generate a JSON report
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess
import xml.etree.ElementTree as ET

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/mental_rotation/mental_rotation.psyexp"
CONDITIONS_FILE = "/home/ga/PsychoPyExperiments/mental_rotation/conditions.csv"
RESULT_FILE = "/tmp/task_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "file_size": 0,
    "is_valid_xml": False,
    # Structure
    "routines": [],
    "has_instructions": False,
    "has_fixation": False,
    "has_trial": False,
    "has_end": False,
    # Trial Logic
    "trial_stimuli_count": 0,
    "has_rotation_logic": False,
    "has_mirror_logic": False,
    "has_keyboard": False,
    "keyboard_uses_corrAns": False,
    # Loop Logic
    "loops": [],
    "has_loop_referencing_conditions": False,
    "psychopy_running": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat()
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

if os.path.isfile(OUTPUT_FILE):
    results["file_exists"] = True
    results["file_size"] = os.path.getsize(OUTPUT_FILE)

    mtime = int(os.path.getmtime(OUTPUT_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    try:
        tree = ET.parse(OUTPUT_FILE)
        root = tree.getroot()

        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True

        # Analyze Routines
        routines_elem = root.find("Routines") or root.find(".//Routines")
        if routines_elem is not None:
            for routine in routines_elem:
                r_name = routine.get("name", "").lower()
                r_info = {"name": r_name, "components": []}
                
                # Identify routine types loosely
                if "instruct" in r_name: results["has_instructions"] = True
                if "fix" in r_name: results["has_fixation"] = True
                if "trial" in r_name: results["has_trial"] = True
                if "end" in r_name or "thank" in r_name: results["has_end"] = True

                for comp in routine:
                    c_type = comp.tag
                    c_props = {}
                    for param in comp:
                        c_props[param.get("name")] = param.get("val")
                    
                    r_info["components"].append({"type": c_type, "props": c_props})

                    # Detailed Trial Logic Checks (only in trial-like routines)
                    if "trial" in r_name:
                        # Count visual stimuli (Text, Image, Polygon, Shape)
                        if any(x in c_type for x in ["Text", "Image", "Polygon", "Shape", "Rect"]):
                            results["trial_stimuli_count"] += 1
                            
                            # Check rotation logic (ori should reference angle)
                            ori = c_props.get("ori", "")
                            if "angle" in ori or "$" in ori:
                                results["has_rotation_logic"] = True
                                
                            # Check mirror logic (flipHoriz or size)
                            # Look for 'mirror', 'matchType', or logic in flip/size
                            flip = c_props.get("flipHoriz", "")
                            size = c_props.get("size", "")
                            if "matchType" in flip or "mirror" in flip or "$" in flip:
                                results["has_mirror_logic"] = True
                            if "matchType" in size or "mirror" in size: # Negative size hack
                                results["has_mirror_logic"] = True

                        # Check Keyboard
                        if "Key" in c_type or "Keyboard" in c_type:
                            results["has_keyboard"] = True
                            corr_ans = c_props.get("correctAns", "") or c_props.get("corrAns", "")
                            if "corrAns" in corr_ans or "$" in corr_ans:
                                results["keyboard_uses_corrAns"] = True

                results["routines"].append(r_info)

        # Analyze Flow/Loops
        flow_elem = root.find("Flow") or root.find(".//Flow")
        if flow_elem is not None:
            for item in flow_elem:
                if "Loop" in item.tag:
                    # The Loop element in Flow just references the loop; details are usually in LoopInitiator properties
                    # But in .psyexp XML, LoopInitiator is a distinct element often found recursively or at root
                    pass
        
        # In .psyexp, loops are often defined by LoopInitiator elements
        # Iterate all LoopInitiator elements in the tree
        for loop in root.iter("LoopInitiator"):
            l_props = {}
            for param in loop:
                l_props[param.get("name")] = param.get("val")
            
            results["loops"].append(l_props)
            
            cond_file = l_props.get("conditionsFile", "")
            if "conditions.csv" in cond_file:
                results["has_loop_referencing_conditions"] = True

    except Exception as e:
        print(f"Error parsing .psyexp: {e}", file=sys.stderr)
        results["xml_error"] = str(e)

# Save results
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="