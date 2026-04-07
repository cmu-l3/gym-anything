#!/bin/bash
echo "=== Exporting configure_calibrated_monitor result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Use Python to query PsychoPy's internal monitor database and parse the XML
# This is more robust than parsing monitor JSONs manually as formats vary
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import xml.etree.ElementTree as ET

# Result dictionary
results = {
    "monitor_found": False,
    "monitor_width": 0,
    "monitor_distance": 0,
    "monitor_resolution": [0, 0],
    "exp_file_exists": False,
    "exp_monitor_link": "",
    "stim_units": "",
    "stim_size": "",
    "stim_sf": "",
    "timestamp": datetime.datetime.now().isoformat()
}

# 1. Query Monitor Database
try:
    from psychopy import monitors
    
    # Check if 'LabView' is in the list of known monitors
    all_mons = monitors.getAllMonitors()
    if "LabView" in all_mons:
        results["monitor_found"] = True
        mon = monitors.Monitor("LabView")
        results["monitor_width"] = float(mon.getWidth())
        results["monitor_distance"] = float(mon.getDistance())
        results["monitor_resolution"] = mon.getSizePix()
except Exception as e:
    print(f"Error querying monitors: {e}", file=sys.stderr)

# 2. Parse Experiment File
EXP_FILE = "/home/ga/PsychoPyExperiments/visual_angle_test.psyexp"
if os.path.isfile(EXP_FILE):
    results["exp_file_exists"] = True
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        
        # Check Experiment Settings for monitor link
        settings = root.find("Settings")
        if settings is not None:
            for param in settings:
                if param.get("name") == "Monitor":
                    results["exp_monitor_link"] = param.get("val", "")
                    
        # Check for Grating Stimulus (can be 'GratingComponent' type)
        # We search for any component that looks like a grating
        for routine in root.iter("Routine"):
            for comp in routine:
                # Check for grating-like components
                if "Grating" in comp.tag:
                    # Extract params
                    for param in comp:
                        name = param.get("name")
                        val = param.get("val")
                        if name == "units":
                            results["stim_units"] = val
                        elif name == "size":
                            results["stim_size"] = val
                        elif name == "sf":
                            results["stim_sf"] = val
    except Exception as e:
        print(f"Error parsing experiment: {e}", file=sys.stderr)

# Save results
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)
    
os.chmod("/tmp/task_result.json", 0o666)
print("Result saved to /tmp/task_result.json")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="