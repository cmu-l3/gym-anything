#!/bin/bash
echo "=== Exporting create_time_to_contact_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import csv
import subprocess

EXP_FILE = "/home/ga/PsychoPyExperiments/ttc_task/ttc_task.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/ttc_task/conditions.csv"
IMG_FILE = "/home/ga/PsychoPyExperiments/ttc_task/road_bg.jpg"
RESULT_FILE = "/tmp/ttc_task_result.json"

results = {
    "exp_exists": False,
    "cond_exists": False,
    "img_exists": False,
    "exp_valid_xml": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    # Analysis fields
    "has_loop": False,
    "conditions_cols": [],
    "background_comp": False,
    "target_comp": False,
    "occluder_comp": False,
    "target_motion_formula": "",
    "target_updates_every_frame": False,
    "occlusion_order_correct": False, # Occluder drawn AFTER target
    "draw_order": [], # List of component names in order
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

# Check files
if os.path.isfile(IMG_FILE):
    results["img_exists"] = True

if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    try:
        with open(COND_FILE, 'r') as f:
            reader = csv.DictReader(f)
            results["conditions_cols"] = reader.fieldnames if reader.fieldnames else []
    except:
        pass

if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["exp_valid_xml"] = True

        # Check Loop
        flow = root.find("Flow")
        if flow is not None:
            for item in flow:
                if "Loop" in item.tag:
                    # Check if it references conditions file
                    for param in item:
                        if param.get("name") == "conditionsFile" and "conditions.csv" in param.get("val", ""):
                            results["has_loop"] = True

        # Check Routine 'trial'
        routines = root.find("Routines")
        if routines is not None:
            for routine in routines:
                if routine.get("name") == "trial":
                    # Iterate components in order
                    # In PsychoPy XML, components are children of Routine.
                    # The order they appear is the draw order (bottom drawn last/on top).
                    
                    target_idx = -1
                    occluder_idx = -1
                    current_idx = 0
                    
                    for comp in routine:
                        comp_type = comp.tag
                        comp_name = comp.get("name")
                        results["draw_order"].append(comp_name)
                        
                        # Identify components by properties
                        is_target = False
                        is_occluder = False
                        is_bg = False
                        
                        # Check params
                        params = {p.get("name"): p for p in comp}
                        
                        # Background check
                        if "Image" in comp_type:
                            if "road_bg" in params.get("image", {}).get("val", ""):
                                is_bg = True
                                results["background_comp"] = True

                        # Target/Occluder check (Polygons)
                        if "Polygon" in comp_type or "Shape" in comp_type:
                            pos_val = params.get("pos", {}).get("val", "")
                            
                            # Target logic: uses 't' and 'speed' in position
                            if ("*t" in pos_val or "* t" in pos_val) and "speed" in pos_val:
                                is_target = True
                                results["target_comp"] = True
                                results["target_motion_formula"] = pos_val
                                
                                # Check update rule
                                updates = params.get("pos", {}).get("updates", "")
                                if updates == "set every frame":
                                    results["target_updates_every_frame"] = True
                            
                            # Occluder logic: static, likely no 't' in pos, maybe name implies it
                            # Or we infer it's the occluder if it's a polygon that ISN'T the target 
                            # and is positioned to the right (x > 0)
                            elif "speed" not in pos_val and "t" not in pos_val:
                                # Simple heuristic: if we already found target, this might be occluder
                                # Or check width/height
                                is_occluder = True
                                results["occluder_comp"] = True

                        if is_target:
                            target_idx = current_idx
                        if is_occluder:
                            occluder_idx = current_idx
                            
                        current_idx += 1

                    # Verify occlusion order
                    # Occluder must be drawn AFTER target to be on top
                    if target_idx != -1 and occluder_idx != -1:
                        if occluder_idx > target_idx:
                            results["occlusion_order_correct"] = True

    except Exception as e:
        print(f"XML parsing error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/ttc_task_result.json
echo "=== Export complete ==="