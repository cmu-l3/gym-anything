#!/bin/bash
echo "=== Exporting Eyewitness Lineup Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Python script to parse the .psyexp file and analyze the grid layout
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import math
import xml.etree.ElementTree as ET

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/eyewitness/lineup_task.psyexp"
RESULT_FILE = "/tmp/eyewitness_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "valid_xml": False,
    "routines": [],
    "lineup_image_count": 0,
    "unique_x_coords": 0,
    "unique_y_coords": 0,
    "grid_rows_detected": 0,
    "grid_cols_detected": 0,
    "has_overlaps": False,
    "mouse_valid_click": False,
    "mouse_clickable_count": 0,
    "mouse_save_params": False,
    "encoding_duration": 0.0,
    "task_start_time": 0,
    "timestamp": datetime.datetime.now().isoformat()
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
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
        results["valid_xml"] = True

        # 1. Analyze Routines
        routines = root.find("Routines")
        if routines is not None:
            for r in routines:
                results["routines"].append(r.get("name"))
                
                # Analyze 'Encoding' routine for duration
                if "encoding" in r.get("name").lower():
                    for comp in r:
                        if comp.tag == "Image" or comp.tag == "Text":
                            for param in comp:
                                if param.get("name") == "stopVal":
                                    try:
                                        results["encoding_duration"] = float(param.get("val"))
                                    except:
                                        pass

                # Analyze 'Lineup' routine for Grid and Mouse
                if "lineup" in r.get("name").lower():
                    images = []
                    mouse_comp = None
                    
                    for comp in r:
                        # Collect Images
                        if comp.tag == "Image":
                            img_data = {"name": comp.get("name")}
                            for param in comp:
                                if param.get("name") == "pos":
                                    val = param.get("val")
                                    # Parse position string "[0, 0]" or "(0.5, -0.5)"
                                    try:
                                        clean_val = val.replace("[","").replace("]","").replace("(","").replace(")","")
                                        parts = [float(x) for x in clean_val.split(",")]
                                        if len(parts) == 2:
                                            img_data["x"] = parts[0]
                                            img_data["y"] = parts[1]
                                    except:
                                        img_data["x"] = 0
                                        img_data["y"] = 0
                            images.append(img_data)
                        
                        # Collect Mouse
                        if "Mouse" in comp.tag:
                            mouse_comp = comp

                    results["lineup_image_count"] = len(images)
                    
                    # Analyze Grid Layout
                    if images:
                        x_coords = sorted(list(set(img["x"] for img in images)))
                        y_coords = sorted(list(set(img["y"] for img in images)))
                        results["unique_x_coords"] = len(x_coords)
                        results["unique_y_coords"] = len(y_coords)
                        
                        # Heuristic: If we have approx 3 unique X and 2 unique Y, that's a 2x3 grid
                        # Use a small tolerance for floating point comparisons? 
                        # For now, strict unique count is usually fine if they used the grid layout tool or typed values.
                        
                        # Check for overlaps (distance < threshold)
                        for i in range(len(images)):
                            for j in range(i + 1, len(images)):
                                dist = math.sqrt((images[i]["x"] - images[j]["x"])**2 + 
                                                 (images[i]["y"] - images[j]["y"])**2)
                                if dist < 0.05: # Threshold depends on units, but 0.05 is small in both norm and height
                                    results["has_overlaps"] = True

                    # Analyze Mouse Interaction
                    if mouse_comp is not None:
                        clickable_str = ""
                        for param in mouse_comp:
                            name = param.get("name")
                            val = param.get("val")
                            
                            if name == "forceEndRoutineOnPress" and val == "valid click":
                                results["mouse_valid_click"] = True
                            
                            if name == "clickable":
                                clickable_str = val
                            
                            if name == "saveParams" and "name" in val:
                                results["mouse_save_params"] = True
                        
                        # Count how many image names are in the clickable string
                        count = 0
                        for img in images:
                            if img["name"] in clickable_str:
                                count += 1
                        results["mouse_clickable_count"] = count

    except Exception as e:
        print(f"Error parsing XML: {e}")

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/eyewitness_result.json
echo "=== Export complete ==="