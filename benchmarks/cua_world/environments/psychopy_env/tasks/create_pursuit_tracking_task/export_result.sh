#!/bin/bash
echo "=== Exporting create_pursuit_tracking_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis to avoid overhead
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess
import xml.etree.ElementTree as ET

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/pursuit_tracking.psyexp"
RESULT_FILE = "/tmp/pursuit_tracking_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "file_size": 0,
    "is_valid_xml": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    
    # Specific component checks
    "has_code_component": False,
    "has_mouse_component": False,
    "has_polygon_component": False,
    
    # Code logic checks (heuristic text search)
    "code_reads_csv": False,
    "code_updates_position": False,
    "code_checks_distance": False,
    "code_updates_color": False,
    
    # Polygon settings checks
    "polygon_dynamic_pos": False,
    "polygon_dynamic_color": False
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
    
    # Check modification time
    mtime = int(os.path.getmtime(OUTPUT_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    try:
        tree = ET.parse(OUTPUT_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True

        # Scan Routines
        routines = root.find("Routines") or root.find(".//Routines")
        if routines is not None:
            for routine in routines:
                for comp in routine:
                    comp_type = comp.tag
                    comp_name = comp.get("name", "").lower()
                    
                    # Check Polygon (Target)
                    if "Polygon" in comp_type:
                        results["has_polygon_component"] = True
                        for param in comp:
                            pname = param.get("name", "")
                            pval = param.get("val", "")
                            pupdates = param.get("updates", "")
                            
                            if pname == "pos" or pname == "position":
                                if "$" in pval and "set every frame" in pupdates:
                                    results["polygon_dynamic_pos"] = True
                            
                            if pname == "color" or pname == "fillColor":
                                if "$" in pval and "set every frame" in pupdates:
                                    results["polygon_dynamic_color"] = True

                    # Check Mouse
                    if "Mouse" in comp_type:
                        results["has_mouse_component"] = True

                    # Check Code Component
                    if "Code" in comp_type:
                        results["has_code_component"] = True
                        
                        # Analyze code content
                        code_begin = ""
                        code_frame = ""
                        
                        for param in comp:
                            pname = param.get("name", "")
                            pval = param.get("val", "")
                            
                            if pname == "Begin Experiment":
                                code_begin = pval
                            if pname == "Each Frame":
                                code_frame = pval
                        
                        # Check CSV reading in Begin Experiment
                        # Look for common patterns: open(), csv.reader, pandas, read_csv, numpy.loadtxt
                        csv_keywords = ["open(", "csv.", "pandas", "pd.read", "loadtxt", "genfromtxt", "trajectory.csv"]
                        if any(k in code_begin for k in csv_keywords):
                            results["code_reads_csv"] = True
                            
                        # Check logic in Each Frame
                        # 1. Position update: assignment usually involves index/counter
                        if "=" in code_frame and ("[" in code_frame or "iloc" in code_frame):
                            results["code_updates_position"] = True
                            
                        # 2. Distance check: sqrt, hypot, or manual (x-x)**2
                        dist_keywords = ["sqrt", "hypot", "**2", "** 2", "distance", "norm"]
                        if any(k in code_frame for k in dist_keywords):
                            results["code_checks_distance"] = True
                            
                        # 3. Color update: if/else logic setting a color string
                        if "if" in code_frame and ("color" in code_frame or "=" in code_frame) and ("red" in code_frame or "green" in code_frame):
                            results["code_updates_color"] = True

    except Exception as e:
        print(f"XML parsing error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/pursuit_tracking_result.json
echo "=== Export complete ==="