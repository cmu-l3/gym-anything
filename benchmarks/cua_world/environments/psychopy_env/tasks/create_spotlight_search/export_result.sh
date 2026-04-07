#!/bin/bash
echo "=== Exporting create_spotlight_search result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess
import xml.etree.ElementTree as ET
import csv

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/spotlight_search.psyexp"
RESULT_FILE = "/tmp/create_spotlight_search_result.json"
STIM_DIR = "/home/ga/PsychoPyExperiments/stimuli"

results = {
    "file_exists": False,
    "file_modified": False,
    "is_valid_xml": False,
    "has_aperture": False,
    "has_mouse": False,
    "has_image": False,
    "has_loop": False,
    "aperture_updates_frames": False,
    "aperture_tracks_mouse": False,
    "conditions_file_valid": False,
    "conditions_file_path": "",
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
    
    # Check modification time
    mtime = int(os.path.getmtime(OUTPUT_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    try:
        tree = ET.parse(OUTPUT_FILE)
        root = tree.getroot()
        results["is_valid_xml"] = True

        # Scan Routines
        routines = root.find("Routines")
        if routines is not None:
            for routine in routines:
                for comp in routine:
                    comp_type = comp.tag
                    comp_name = comp.get("name", "")

                    # Check for Mouse
                    if "Mouse" in comp_type:
                        results["has_mouse"] = True
                    
                    # Check for Image
                    if "Image" in comp_type:
                        results["has_image"] = True
                    
                    # Check for Aperture
                    if "Aperture" in comp_type:
                        results["has_aperture"] = True
                        
                        # Check Aperture Logic
                        for param in comp:
                            pname = param.get("name")
                            pval = param.get("val", "")
                            pupdates = param.get("updates", "")
                            
                            if pname == "pos":
                                # Check if it links to mouse
                                # Flexible check: looks for "mouse" and "getPos" or similar
                                if "mouse" in pval.lower() and "getpos" in pval.lower():
                                    results["aperture_tracks_mouse"] = True
                                
                                # Check if updates every frame
                                if pupdates == "set every frame":
                                    results["aperture_updates_frames"] = True

        # Check Flow/Loop for conditions file
        flow = root.find("Flow")
        if flow is not None:
            for item in flow:
                if "Loop" in item.tag:
                    results["has_loop"] = True
                    for param in item:
                        if param.get("name") == "conditionsFile":
                            cond_file = param.get("val", "")
                            # Resolve relative paths
                            if cond_file:
                                full_path = os.path.join(os.path.dirname(OUTPUT_FILE), cond_file)
                                if not os.path.exists(full_path) and os.path.exists(os.path.join("/home/ga/PsychoPyExperiments", cond_file)):
                                     full_path = os.path.join("/home/ga/PsychoPyExperiments", cond_file)
                                
                                results["conditions_file_path"] = full_path
                                
                                # Verify conditions file content
                                if os.path.exists(full_path):
                                    try:
                                        with open(full_path, 'r') as f:
                                            reader = csv.reader(f)
                                            rows = list(reader)
                                            if len(rows) > 1: # Header + data
                                                # Check if images referenced actually exist
                                                content = str(rows).lower()
                                                if "array_1" in content or "array_2" in content:
                                                    results["conditions_file_valid"] = True
                                    except:
                                        pass

    except Exception as e:
        print(f"Error parsing XML: {e}")

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_spotlight_search_result.json
echo "=== Export complete ==="