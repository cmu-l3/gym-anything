#!/bin/bash
echo "=== Exporting RDK Motion Coherence result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis to avoid multiple interpreter startups
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess
import xml.etree.ElementTree as ET

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/motion_coherence.psyexp"
RESULT_FILE = "/tmp/task_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "file_size": 0,
    "is_valid_xml": False,
    "has_dots_component": False,
    "dots_settings": {},
    "has_instructions": False,
    "has_fixation": False,
    "has_trial_routine": False,
    "has_keyboard": False,
    "has_loop": False,
    "loop_conditions_file": "",
    "coherence_variable_used": False,
    "direction_variable_used": False,
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

if os.path.isfile(OUTPUT_FILE):
    results["file_exists"] = True
    results["file_size"] = os.path.getsize(OUTPUT_FILE)
    
    # Check if modified after task start
    mtime = int(os.path.getmtime(OUTPUT_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    try:
        tree = ET.parse(OUTPUT_FILE)
        root = tree.getroot()
        
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True

        # Check routines
        routines = root.find("Routines") or root.find(".//Routines")
        if routines is not None:
            for routine in routines:
                rname = routine.get("name", "").lower()
                
                # Check routine types based on content or name
                if "instruct" in rname:
                    results["has_instructions"] = True
                if "fix" in rname:
                    results["has_fixation"] = True
                if "trial" in rname:
                    results["has_trial_routine"] = True

                # Check components inside routines
                for comp in routine:
                    ctype = comp.tag
                    cname = comp.get("name", "")
                    
                    # Dots Component Check
                    # Type is usually "DotsComponent" or similar in XML
                    if "Dots" in ctype or "Dots" in str(comp.attrib.get("type", "")):
                        results["has_dots_component"] = True
                        
                        # Check Dots parameters
                        for param in comp:
                            pname = param.get("name", "")
                            pval = param.get("val", "")
                            
                            results["dots_settings"][pname] = pval
                            
                            if pname == "coherence" and ("$coherence" in pval or "coherence" in pval):
                                results["coherence_variable_used"] = True
                            if pname == "dir" and ("$direction" in pval or "direction" in pval):
                                results["direction_variable_used"] = True
                                
                    # Keyboard Check
                    if "Keyboard" in ctype or "Keyboard" in str(comp.attrib.get("type", "")):
                        # If it's in the trial routine, count it
                        if "trial" in rname:
                            results["has_keyboard"] = True

        # Check Loops
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            for item in flow:
                if "Loop" in item.tag:
                    results["has_loop"] = True
                    for param in item:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname == "conditionsFile":
                            results["loop_conditions_file"] = pval

    except Exception as e:
        print(f"Error parsing XML: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
    
os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="